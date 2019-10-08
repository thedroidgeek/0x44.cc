---
layout: post
title: Unlocking IAM's Nokia G-240W-A router (Part 1)
excerpt_separator:  <!--more-->
categories:
  - Reversing
---


### Context


As we recently upgraded our home internet to try out Maroc Telecom's 100mbps fiber offer, I've noticed that the Nokia router they installed had horrible Wi-Fi speed - the max I could to get standing next to it was around 60mbps down, while in the opposite room, the speed was always under 10mbps.

What's interesting is the fact that it had decent range - I get full bars most of the time, and my Wi-Fi adapter reports a 300mbps data rate.

This got me intrigued, so I tried to take a look at what's running inside this thing.

![](/assets/media/nokia-g-240w-a.png)


### First look


Doing a little online research, you will find out that the firmware on this router had quite a [bad](https://medium.com/tenable-techblog/gpon-home-gateway-rce-threatens-tens-of-thousands-users-c4a17fd25b97){:target="_blank"}{:rel="noopener noreferrer"} [history](https://www.websec.ca/publication/Blog/backdoors-in-Zhone-GPON-2520-and-Alcatel-Lucent-I240Q){:target="_blank"}{:rel="noopener noreferrer"}.

There's various blog posts showing that routers running on similar firmware were found to be vulnerable to unauthenticated RCE vulnerabilities, and had hardcoded Telnet backdoor accounts.

The first thing I did, of course, is log into the web administration portal - there's a sticker in the back of the router with the credentials, which seem device specific, which is good... Or so I thought - as it turns out there's a known 'superuser' account for the web panel, which has a default password: AdminGPON / ALC#FGU

![](/assets/media/nokia-ont-back.png)

After fiddling with the web interface, trying to force the WiFi to use 802.11n and 40MHz bandwidth, I've noticed no difference. It was time to take a deeper dive.

According to someone at [lafibre.info](https://lafibre.info/cryptographie/probleme-dacces-en-ligne-de-commande-a-mon-ont/){:target="_blank"}{:rel="noopener noreferrer"} forum, Telnet access to this router was possible via the ONTUSER / SUGAR2A041 'backdoor' account, before an update was deployed sometime in June 2018.

I've tried the web account credentials as well as any backdoor credentials I was able to find, to no avail. The fact that Telnet access locks for 5 minutes every 3 failed attempts didn't help as well.

That's when I've decided to take a look at the configuration backup and restore functionnality.


### Analysing the backup file 


As the 'AdminGPON' user, you're able to import and export the router configuration.

![](/assets/media/nokia-ont-backup-restore.png)

As the exported config.cfg file wasn't plain-text, I've tried looking for magic values, and binwalk was able to find something right away:
```
$ binwalk config.cfg

DECIMAL     HEXADECIMAL   DESCRIPTION
--------------------------------------------------------------------
20          0x14          Zlib compressed data, default compression
```

Being the lazy guy that I am, I've opened the file in a hex editor, stripped out the first 20 bytes, then pasted the hex dump in [CyberChef](https://gchq.github.io/CyberChef/){:target="_blank"}{:rel="noopener noreferrer"}, and a huge xml file showed up. Bingo!

![](/assets/media/cyberchef-zlib.png)

Exploring the xml a bit, I was able to spot the Telnet credentials (or so I thought):

```xml
<TelnetEnable rw="RW" t="boolean" v="True"></TelnetEnable>
<TelnetUserName ml="256" rw="RW" t="string" v="admin"></TelnetUserName>
<TelnetPassword ml="256" rw="RW" t="string" v="OYdLWUVDdKQTPaCIeTqniA==" ealgo="ab"></TelnetPassword>
```

Alrighty, now how do I crack/decrypt this admin password?

Since this was 128-bit base64 encoded data, I tried MD5'ing known passwords, then I tried every other known hashing algorithm, but none of them gave me anything - so it has to be either salted or encryption.

Exploring a little further, I've found another Telnet credential thingy:

```xml
<TelnetSshAccount. n="TelnetSshAccount" t="staticObject">
<Enable rw="RW" t="boolean" v="False"></Enable>
<UserName ml="64" rw="RW" t="string" v=""></UserName>
<Password ml="64" rw="RW" t="string" v="" ealgo="ab"></Password>
</TelnetSshAccount.>
```

But it's unused... Damn.

Now that modifying the configuration file seemed more necessary, I tried to take a second look at the exported config.cfg.


### Modifying the backup file


I kept exporting backup files while changing the router settings to regenerate different files for me to look at.

After a few comparisons with the not so naked eye (I wear glasses), I was able to tell that a single 32-bit value in the header was always changing radically, so this must be a checksum of sorts.

![](/assets/media/cfg-header-comparison.gif)

Now before guessing what's being checksumed and how, I first need to know where the zlib data ends and if there's something else after it.

So I tried recreating the compressed chunk, which was pretty trivial, again thanks to CyberChef.

It turns out there's about 300 bytes after it that are unknown, but still, CRC32 on the deflated data gave the exact value at offset 8, which was in big endian. Yay!

Now the null bytes made more sense, and it was clear to me that the other values next to the checksum must be positive integers.

Soon after, I was able to figure out that the first one (+4) was the length of the deflated data, while the second one (+C) was the size of the xml file.

Since in all the config.cfg files that I've exported, the rest of the bytes were static, this seemed enough for me to generate my own backup file, and as expected, uploading my crafted config.cfg worked!

Here's a [simple python script](https://gist.github.com/{{ site.github_username }}/80c379aa43b71015d71da130f85a435a){:target="_blank"}{:rel="noopener noreferrer"} I've made for this purpose, for those interested.


### Unlocking Telnet and SSH access


So I took the password that I've set for the the 'AdminGPON' web account from:

```xml
<WebAccount. n="WebAccount" t="staticObject">
<Enable rw="RW" t="boolean" v="True"></Enable>
<Priority max="10" min="1" rw="RW" t="unsignedInt" v="1"></Priority>
<UserName ml="64" rw="RW" t="string" v="AdminGPON"></UserName>
<Password ml="64" rw="RW" t="string" v="[REDACTED]" ealgo="ab"></Password>
<PresetPassword ml="64" rw="R" t="string" v="xEKUBYh1yT50dQFNwAr/5A==" ealgo="ab"></PresetPassword>
</WebAccount.>
```

And used it for `TelnetPassword` config node, but logging in as `admin` still didn't work.

Since I can now generate these password hashes (or whatever they are) also, I tried changing my 'AdminGPON' password and comparing the resulting value with the `TelnetPassword` one (`OYdLWUVDdKQTPaCIeTqniA==`), and after a couple of tries, I've realized that the password was simply: `admin`.

Since we all know that admin:admin is the first login combo that I, and everyone else, use, when trying to login on any panel that's not ours, it seems like they now ignore these credentials.

But don't worry, `TelnetSshAccount` comes to the rescue:

```xml
<TelnetSshAccount. n="TelnetSshAccount" t="staticObject">
<Enable rw="RW" t="boolean" v="True"></Enable>
<UserName ml="64" rw="RW" t="string" v="hexdd"></UserName>
<Password ml="64" rw="RW" t="string" v="[REDACTED]" ealgo="ab"></Password>
</TelnetSshAccount.>
```

I've set the 'Enable' flag to true, chose a username, and copied my password, and lo and behold, after a reboot, we have root!

![](/assets/media/root-nokia-ont.png)

Stay tuned for more. :)