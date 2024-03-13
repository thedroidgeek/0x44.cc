---
layout: post
title: 'Reverse engineering a car key fob signal (Part 1)'
excerpt_separator:  <!--more-->
categories:
  - radio
---

### Context

I've had the curiosity to explore radio communication protocols for a few years now, ever since I've started fiddling around with an RTL-SDR dongle. I always had the goal of figuring out how data is transmitted in remote controls (car key fobs particularly), trying replay attacks, and other possible attack vectors.

Despite capturing some car key fob signals over the years, I haven't had the chance of doing meaningful analysis on them, and that's mainly due to the limited access I had to cars I could test on.

This blog post aims to bring the uninitiated through my journey of having successfully reverse engineered and replayed a car's key fob signal last year, starting from the very basic concepts of radio frequency and going all the way through my entire thought process while I was working on this project.

Another goal I guess is to also prove that most cars are definitely not that easy to steal using replay attacks (unless it's a [Honda](https://rollingpwn.github.io/rolling-pwn/), lol), despite Canada's recent ban of the Flipper Zero, and them claiming the risk warrants the ban of a device made of very cheap and accessible wireless modules.

### Hardware used

#### RTL-SDR

I've had my first dive into the world of radio frequency back in 2016 when I learned that a very cheap (~$10) terrestrial TV/radio USB dongle can easily be turned into a multi-purpose RF receiver to inspect and decode pretty much anything happening in the range of 24 to 1750 MHz - this device is widely known as 'RTL-SDR':

![](/assets/media/rtl-sdr.png)

The secret why this cheap device is very powerful, is the simple fact that it uses a chip which allows the use of [SDR (software defined radio)](https://en.wikipedia.org/wiki/Software-defined_radio). It turns out that this chip (RTL2832U) allowed skipping the signal processing that usually happens on the hardware-level which converts the raw signal into 'meaningful' data to be used by the host device (a TV/radio feed in the case of this device).

By having direct access to the raw I/Q data, we can receive, visualize and save pretty much any signal in raw format, without needing to know the specifics of the RF configuration used to transmit (modulation, bandwidth, data rate, etc.), since we can analyze/process the raw data ourselves. This effectively gives us a window to scan for virtually any activity on the radio spectrum under the 1.7 GHz frequency.

#### Flipper Zero

The Flipper Zero is an electronic gadget which attracted a lot of attention lately for being a hacker/troll's ultimate Swiss knife, since it hosts a bunch of wireless hardware modules that allow 'interacting with' everyday electronics and consumer appliances.

![](/assets/media/flipper-zero.jpg)

The module that's interesting to us in the Flipper is the Sub-GHz one, which is essentially a [CC1101](https://www.ti.com/product/CC1101) chip that supports frequencies that are typically used in wireless consumer devices, and that are under 1 GHz, hence the name of the module.

It's important to note, however, that one could just buy the CC1101 module separately ($5+) and make it work with an Arduino/Raspberry Pi or simply a USB-to-TTL adapter, but the Flipper is definitely cooler and more practical. ¯\\\_(ツ)\_/¯

#### CC1101 vs RTL2832U

The CC1101 chip in the Flipper Zero, unlike the RTL2832U chip that's on the RTL-SDR, is actually a transceiver module (supports sending and receiving), which means the Flipper Zero is the device we'll be using to send signals.

However, the CC1101 chip doesn't support SDR, which means that it would only send back data that it had completely processed. In other terms, the CC1101 will only be useful to us if we set the right RF configuration of the transmitted signal.

|                   | Flipper Zero (CC1101) | RTL-SDR dongle (RTL2832U) |
| ----------------- | --- | --- |
| Receiving signals | ✔️ | ✔️ |
| Sending signals   | ✔️ | ❌ |
| Receiving/analyzing raw signals | ❌ | ✔️ |

***Note:*** Transceiver SDR devices do exist of course, but they tend to be very pricey.

### Radio frequency signal basics (*oversimplified*)

Now that we know a bit about the hardware we'll be using, let's go through some minimum basic concepts that are needed to tackle this subject.

#### Intro

Radio frequency transmissions use radio waves, which are a type of electromagnetic radiation, in order to send signals.

These waves are of a typically higher frequency than the original signal we're transmitting and this is to ensure reliability in sending data, since signals can have varying characteristics that make sending them as radio waves impractical and susceptible to interference and weak travel distance.

These waves are called carrier waves, since they are essentially modified to carry the original signal reliably through the air (more on this below).

Let's take a look at *some* of the basic information needed to send/receive a radio signal:

#### Frequency

This one is self-explanatory, it's the number of times a second a carrier wave occurs. Frequency affects the wavelength (the higher the frequency the shorter the waves). This parameter is also typically used to define the communication channel.

#### Modulation

This refers to the way a signal is represented in the radio waves. The two most common modulation types, which I'm sure most people already know of, are:

**AM** (*amplitude* modulation) and **FM** (*frequency* modulation).

The difference between these is simply the fact that for AM, the signal is modulated (encoded) in *amplitude* (or strength), which roughly means that the *change* in signal *strength* on the carrier waves is how the data is represented.

For FM, as one can guess, the data is rather modulated in *frequency*. So, changes in the frequency of the waves are used here to determine the data.

This is well visualized in this animation I found on Wikipedia (the 'signal' graph represents the data we're trying to transmit):

![](/assets/media/radio-fm-vs-am-anim.gif)

Modulations can also have different subtypes and characteristics which we'll talk about later on.

#### Bandwidth

This refers to the range of frequencies occupied by a modulated RF signal, or in other words, the difference between the highest and the lowest frequency a modulated signal can have. This essentially dictates the amount of data a signal can carry.

Since the rest of the radio characteristics are not terribly important for us to know at this stage, let's move on to the fun stuff!

### Visual analysis

#### SDR#

[SDR#](https://airspy.com/download/) is a free, intuitive, computer-based DSP (Digital Signal Processing) application for SDR written in C# with a focus on performance. It allows visualizing the radio spectrum in real time, and supports the demodulation of some common modulations. It also supports third-party plugins for custom modulations and integrations.

We'll be using this software for our signal discovery and initial analysis phase.

#### Signal discovery

By tuning into the 433.92 MHz frequency with our RTL-SDR dongle plugged in (using the WinUSB driver instead of the stock DVB-T one), we can watch the activity of most remote controls in close proximity (433.92 MHz being the standard unregulated frequency in the EU and other neighboring countries, including Morocco, where I live).

On each car key fob button press we instantly notice that there's 3 successive short bursts generated, as can be seen on the waterfall view under the spectrum visualizer:

![](/assets/media/sdrsharp-key-fob-433.png)

<small style="display: block; text-align: center;">SDR# visualizing the key fob signal (X axis = frequency, Y axis = signal intensity)</small>

We can also notice that the signal has two major 'peaks' on both sides of the 433.92&nbsp;MHz frequency (the red line in the middle is the exact tuning frequency).

Doing some research on common modulation schemes, we come across 2-FSK that sounds interesting:

#### 2-FSK

FSK stands for Frequency-Shift Keying, which is a frequency modulation scheme in which data is encoded on a carrier signal by periodically shifting the frequency of the carrier between several discrete frequencies.

Pretty straightforward so far, sounds like we're dealing with FM here.

The interesting part is the '2' however, which here stands for the number of channels used in the encoding. So, we're actually encoding binary data in two separate frequencies here, one for the **0** and the other for the **1**, which would explain the two peaks we're noticing.

***Note:*** One might wonder what the other smaller 'peaks' are in that screen capture - those are basically unwanted frequencies that are generated accidentally by the emitter chip, due to the cheap nature of the hardware, and due to the very close proximity of the remote and the antenna. So, it's just a bunch of 'noise' that we can safely ignore.

### Practical analysis

Now that we checked what the signal looks like visually, let's explore how we can work on analyzing it in order to read the bits from the RF waves in hopes to spot some sort of structure/consistency.

#### Universal Radio Hacker

As the README of its repository states, the [Universal Radio Hacker (URH)](https://github.com/jopohl/urh) is a complete open-source suite for wireless protocol investigation with native support for many common SDRs. URH allows easy demodulation of signals combined with an automatic detection of modulation parameters making it a breeze to identify the bits and bytes that fly over the air.

This is precisely the software we need to decode radio waves into bits.

As we open URH, we're invited to either open a file or record directly from a device.

Before recording, we have to select the source device, and set some basic radio parameters (I actually only made sure to put the right frequency and left everything else as default):

![](/assets/media/urh-record-dialog-rtlsdr.png)

After recording a signal, URH will try to autodetect the right configuration to use when decoding the radio waves.

On my initial recordings, I wasn't able to get URH to find the right parameters for me, which gave me wrong results. I have however later figured out that recording multiple repetitive signals in one go increases the chance that URH will figure out the right configuration, which turned out to be in my case: 50 samples/symbol, FSK.

![](/assets/media/urh-signal-interpretation.png)

Zooming in on one of the signals, we notice the 3 bursts we identified on SDR# (the second of which is made of 3 separate ones - so we have 5 sections to analyze now):

![](/assets/media/urh-signal-zoom-in.png)

For each of these sections, a bit sequence is automatically extracted, which we can also convert to hex for a better visualization:

![](/assets/media/urh-signal-zoom-in-hex.png)

We can already notice a lot of consistency and repeating patterns in the bytes, which is a sign that we're on the right path.

However, to my eyes, we're still missing something here, because we notice the same 5&nbsp;hex digits being repeated, with a lot of 0x55 bytes (01010101) also, which is pretty intriguing.

Going over to the next tab labeled 'Analysis', we can see the bytes we've just extracted from each burst, each represented in a line, and there's a decoding option that shows up with a bunch of curious algorithms:

![](/assets/media/urh-analysis-decoding-options.png)

By brute forcing my way and trying them consecutively, I noticed that one of them (Manchester II) converted all the 0x55 bytes to null ones, and without producing any decoding errors:

![](/assets/media/urh-manchester-decoded.png)

These bytes look more legit now.

##### Manchester encoding

[Manchester](https://en.wikipedia.org/wiki/Manchester_code) is a very simple digital modulation scheme that ensures that the signal never remains at logic low or logic high for an extended period of time, and also converts the data signal into a data-plus-synchronization signal (for [clock recovery](https://en.wikipedia.org/wiki/Clock_recovery)).

These characteristics are very useful when sending digital data over analog mediums that tend to be susceptible to noise and interference.

In Manchester, binary data is encoded in two opposite bits, therefore:

**0** becomes **01** and **1** becomes **10** (or the other way around, depending on the convention):

![](/assets/media/manchester-visualization-wiki.png)


Let's go back and continue our investigation.

By doing some manual examination and comparison of the different captures, we're able to note that each button press generates a signal with the following characteristics:

1. A <span style="color:yellow">long burst</span> with no data (decodes to 100 null bytes).
2. 3 bursts which look very similar with only 2 bytes partially <span style="color:red">changing</span>.
3. A <span style="color:lightgreen">final burst</span> which is shorter but still looks fairly similar to the previous 3 bursts.

![](/assets/media/urh-initial-signal-structure-highlight.png)

I decided to look more closely at the 3 bursts (let's call them packets) in the middle since they seem to be the important part of the signal, and I was quickly able to spot what seems to be an <span style="color:deepskyblue">incremental ID</span> which increases by 1 on each new signal:

![](/assets/media/urh-incremental-id-spotted.png)

To be able to move forward with our analysis, we must learn about a very important remote control security mechanism:

#### Rolling codes

A rolling code is used in keyless entry systems to prevent a simple form of replay attack, where an eavesdropper records the transmission and replays it at a later time to cause the receiver to 'unlock'. Such systems are typical in garage door openers and keyless car entry systems. More on [Wikipedia](https://en.wikipedia.org/wiki/Rolling_code).

The gist of this system is that the key and the car both 'agree' on a cryptographically secure algorithm in order to generate rolling codes that are used to authenticate the remote.

These keys are generated and tracked using a *counter* which has to stay in sync between the remote and the car. This ensures that the car doesn't reuse an old key, and that the remote always generates fresh keys.

An example of a rolling code implementation is pictured below <small>(credits: [RuhrSec 2017](https://www.youtube.com/watch?v=8P_Wgl89jPU))</small>:

![](/assets/media/rolling-code-explanation.png)

* **uid**: ID of the car/remote link
* **enc<sub>k</sub>**: Implementation of the rolling code algorithm
* **ctr**: The car's counter
* **ctr'**: The remote's counter

The validity window permits the remote to not go out of sync if the car doesn't happen to receive the signal (typically with a max of 255 out-of-range button presses on most implementations, after which the remote has to be manually resynchronized).


Alright, let's go back to the drawing board.

Since we now know that rolling codes are *cryptographically* secure, it becomes easy for us to spot the <span style="color:lightgreen">part of the signal</span> responsible for this implementation (which would be the one with the highest entropy):

![](/assets/media/urh-rolling-code-spotted.png)

We can also make the assumption that the <span style="color:deepskyblue">incremental ID</span> we've identified earlier is the counter for the rolling code system. As it also conveniently sits right next to the code.

By comparing lock and unlock signals, I was also able to quickly spot <span style="color:plum">the byte</span> responsible for the command (8 = unlock, 4 = lock):

![](/assets/media/urh-command-byte-spotted.png)

Now all that's left for us to guess from the signal's 'variable parts' are the two <span style="color:red">red changes</span> we marked earlier:

**1)** For the first one, we notice that the same values repeat themselves across the other captured signals.

Converting the 3 values to binary, we notice the following:

* 0x6: **01**10
* 0xA: **10**10
* 0xE: **11**10

Interesting, looks as if it's packing some sort of sequence number for the packets.

And what if we check the final (4th) packet as well?

* 0x13: **100**11

Yup, our theory seems to check out <small>(ignore the lowest bit that changed here)</small>.

**2)** Let's guess the last byte now.

We can notice that this one not only changes for each packet, but it does so completely across all signals as well.

Seeing that this is the last byte on the packet and that it changes pretty randomly, leads me to suspect this being a checksum.

One thing we can try doing is a XOR of this byte with the other byte we just analyzed, to see if we can end up with a static value (since pretty much *everything* besides these two bytes actually stays *static* when it comes to the 3 rolling code packets).

Let's try with these two examples:

![](/assets/media/urh-checksum-theory-test.png)

Example 1:

* 0x06 ^ 0xB9 = **0xBF**
* 0x0A ^ 0xB5 = **0xBF**
* 0x0E ^ 0xB1 = **0xBF**

Example 2:

* 0x06 ^ 0xCC = **0xCA**
* 0x0A ^ 0xC0 = **0xCA**
* 0x0E ^ 0xC4 = **0xCA**

Bingo. This is definitely a XOR checksum.

By applying XOR on all the bytes of the packets, we notice that the value always ends up being off by 1:

![](/assets/media/urh-bad-checksum.png)

This leads us to conclude that the first 2 bytes of the packet are likely excluded from the checksum (which is where the 1 is coming from):

![](/assets/media/urh-synchronization-bytes.png)

And this actually makes sense, since these bytes would act here as a [syncword](https://en.wikipedia.org/wiki/Syncword) to synchronize the receiver and indicate the beginning of the data.

**Note:** If you're wondering about the utility of the initial <span style="color:yellow">long burst</span> highlighted in yellow in the captures - that one serves to basically wake up the radio receiver and prepare it to start receiving data (since it goes in an idle low power state on inactivity). And if you're also wondering why the remote sends 3 packets with roughly the same data, it's simply to insure some sort of reliability. In case one of the packets gets corrupted on the way (which we saw happen on an earlier screenshot).


#### Final result

After labeling the rest of the bytes to my best guess, this is the result I ended up with:

![](/assets/media/urh-final-labelization.png)

Neat. We've just reverse engineered a car key fob signal.

Tune in next time when I (hopefully) write about how I integrated support for this signal format on the Flipper Zero in order to be able to read, re-serialize, and replay it.


Thanks for reading!

**Note:** If you’ve noticed inaccurate information, or room for improvement regarding this article, and would like to improve it, feel free to [submit a pull request](https://github.com/thedroidgeek/0x44.cc/edit/master/_posts/2024-03-13-reversing-a-car-key-fob-signal.md) on GitHub.
