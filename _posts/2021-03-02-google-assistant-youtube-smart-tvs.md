---
layout: post
title: Google Assistant YouTube command for smart TVs
excerpt_separator:  <!--more-->
categories:
  - automation
---


### Context


After I've noticed my 2019 Samsung TV had support for Google Assistant commands for basic controls such as power, volume, channel, input source, etc., I thought it would be cool to also be able to cast media content using my voice, but I then realized that the only officially supported TVs were labeled 'Chromecast-enabled', and that people without those generally end up buying the Chromecast TV stick, for the 'full compatibility', which sounds like a waste when you already own a 'smart' TV.

As YouTube takes up the largest part of my 'media consumption', one day, ~~and after procrastinating for months,~~ I went ahead and checked out the inner-workings of the existing casting functionnality, by casting YouTube videos from the Android app to the TV, to try to figure out a way to automate that process, to then link it to the Google Assistant.


### DIAL protocol


By doing a quick capture of the network traffic between the phone and the TV - by using the Intercepter-NG app (requires root), I've already noticed a very simple and easy-to-spot HTTP endpoint that was being hit during the cast connection:

`http://tizen:8080/ws/apps/YouTube` ('tizen' being the TV's LAN hostname)

A quick search online revealed that this endpoint is part of a protocol called DIAL, for Discovery and Launch, which is used to initiate applications on "1st screen" devices, such as TVs, via small factor ("2nd screen") devices, such as phones and tablets. ([More on Wikipedia](https://en.wikipedia.org/wiki/Discovery_and_Launch))

It turns out that a simple empty POST request to the previously mentionned endpoint would launch the application on the target TV, and a GET would return various metadata around the application, in XML format, including its status (running/stopped), and other application-specific information:

```xml
<service xmlns="urn:dial-multiscreen-org:schemas:dial" xmlns:atom="http://www.w3.org/2005/Atom" dialVer="2.1">
  <name>YouTube</name>
  <options allowStop="true"/>
  <state>running</state>
  <version>2.1.493</version>
  <link rel="run" href="run"/>
  <additionalData>
    <testYWRkaXR>c0ef1ca</testYWRkaXR>
    <screenId>[REDACTED]</screenId>
    <theme>cl</theme>
    <deviceId>[REDACTED]</deviceId>
    <loungeToken>AGdO5p9wG5CgVGkvneeZ4MSaEJMnJrailH5e4YBwEa4zDZl9C-J5Hju0dxT-PzOJsNQcojxt5ih1K5cY72mPFR-IJUVBC-KU-WaLBriZMnc9KFv1DBLXlhY</loungeToken>
    <loungeTokenRefreshIntervalMs>1500000</loungeTokenRefreshIntervalMs>
  </additionalData>
</service>
```

Great, we now have an easy way of launching the app on the target TV so that it's ready to receive casted content.

After doing more research, it seems there's also an 'easy' way of playing actual videos using this same endpoint, by simply adding a `v` parameter on the body of the POST request, which would be the YouTube video ID.

However though, it seems that this method was recently (late 2020) rendered useless, as it now requires manual confirmation on the TV each time a video is requested.

![](/assets/media/yt-shady-cast-prompt.jpg)

Time to dig deeper.


### YouTube cast functionnality


In order to proceed with further network traffic inspection, it was needed to achieve HTTPS interception, which would require bypassing SSL-pinning on the Android YouTube app, in order to be able to decrypt its traffic.

Luckily though, it turns out that the Google Chrome browser also supports the casting functionnality on YouTube - so I've simply fired up [Fiddler](https://www.telerik.com/download/fiddler) and started watching the web requests.

When a compatible TV is discovered, a casting icon pops up on the YouTube player control bar, like so:

![](/assets/media/yt-cast-icon.png)

After clicking the icon and choosing the cast device, the YouTube player starts acting as a remote.

Behind the scenes, a private YouTube API called 'Lounge' is used, in order to do the pairing and the remote control functionnality for YouTube Leanback (big screen) devices.

![](/assets/media/yt-lounge-api-capture.png)

By analysing these requests, I've noticed that the API was fairly complicated, with a mix of body and URL parameters, comprising tokens, IDs, as well as some weird changing alphanumeric values.

![](/assets/media/yt-lounge-api-params.png)

The responses were also seemingly in a custom JSON-based format.

```json
B2
174
[[105,["onStateChange",{"currentTime":"50","duration":"318.321","cpn":"7s_Qx1i3xE4fXNVX","loadedTime":"50","state":"3","seekableStartTime":"0","seekableEndTime":"318.3"}]]
]

0
```

However, I was able to find some very useful code on GitHub, which saved me the hassle of reverse engineering the API, which quite frankly, I might've gave up doing. &#x1F440;


### youtube-remote by @mutantmonkey 


[youtube-remote](https://github.com/mutantmonkey/youtube-remote) allows us to play/queue a video, and pause/resume the playback, using the YouTube Lounge API.

```
usage: remote.py [-h] (--play PLAY | --queue [QUEUE ...] | --pause | --unpause)

Command-line YouTube Leanback remote

optional arguments:
  -h, --help           show this help message and exit
  --play PLAY          Play a video immediately
  --queue [QUEUE ...]  Add a video to the queue
  --pause              Pause the current video
  --unpause            Unpause the current video
```

The first phase is the pairing phase.

Upon running the script, you are instructed to provide a pairing code - which is seemingly the method used to pair with 'old-school' leanback devices, that aren't necessarily on the same network and/or don't support casting protocols like DIAL.

The pairing code is then used to retreive the `loungeToken` using the `/api/lounge/pairing/get_screen` endpoint.

We can skip this part, as in our case, the TV seems to always allocate its own `loungeToken`, as seen on the ['DIAL endpoint' response](#dial-protocol).

After commenting out the pairing code part, and manually assigning the `loungeToken` of the TV, the script worked!

![](/assets/media/yt-remote-demo.gif)

Sweet! We now have a decent way of playing YouTube videos on the TV.


### Automation


Now that we've figured out the main part, it's now time to find a method of automating the whole process.

First off, [IFTTT](https://ifttt.com/) allows us to have [custom Google Assistant commands](https://support.google.com/googlenest/answer/7194656), so we can use that as a starting point.

IFTTT has a [webhook plugin](https://ifttt.com/maker_webhooks), which would allow us to receive actions following a Google Assistant command, via HTTP.

But in order for us to receive these commands locally, we would have to expose a local webserver to the internet, which means that we have to use either a reverse proxy service such as [ngrok](https://ngrok.com/) or [localtunnel](https://localtunnel.me/), or do port forwarding on the router, and configure a dynamic DNS (I went with the former option, for reference).

So, In short, here's the complete execution flow:

1. "Hey Google, `searchQuery` on YouTube."
2. Google Assistant executes the IFTTT command.
3. Which calls IFTTT's Maker Webhooks on a public webhook.
4. Which forwards to our local webserver.
5. Which would execute the following sequence:
  - Do a YouTube video search by scraping `youtube.com/results?search_query={searchQuery}`, in order to find/parse the video ID.
  - Launch the YouTube app on the TV (POST :8080/ws/apps/YouTube).
  - Wait for the `loungeToken` to be available (GET).
  - Use the Lounge API to play the video on the TV (youtube-remote on GitHub).


### Extras

#### 1. Multiple search results

As my TV already supported Google Assistant commands such as next and previous, I thought about queuing a dozen of YouTube videos that come up on the search, instead of just one, so I can go through the search results, in case the video I want is not the first one to show up.

After I've noticed that queuing each video would show an annoying notification on the TV, I looked for better way to do the job.

Luckily, after some analysis of YouTube JS code, and some trial and error, I was able to figure out how to use the Lounge API command `setPlaylist`, which takes 2 arguments, `videoId` and `videoIds` - the first one is the initial video to play, while the second one is a comma-separated list of the rest of the videos to be queued.

Cool, no more pesky notifications, and a single command can do it all now.

#### 2. Wake-on-LAN

I've also implemented Wake-on-LAN, so that the TV would turn on in case it was off.

This is especially useful since, for some reason, there's a [known issue](https://community.smartthings.com/t/samsung-tv-cant-turn-on/114960), at least on some select models, where if the TV is connected via Ethernet instead of Wi-Fi, it loses connection to [SmartThings](https://www.smartthings.com/) soon after it's turned off - which means you can't turn it on from the cloud/Google Assistant.

#### 3. YouTube player UI visibility

Lastly, a small UX improvement: I send a pause + play command (you can send multiple commands on a single request) after the `setPlaylist` command, to force the YouTube player UI to show up initially (so that one's able to see the video title), as it doesn't do so by default when casting.

### Demo

<p style="position: relative; padding: 30px 0px 57% 0px; height: 0; overflow: hidden;"><iframe src="https://www.youtube.com/embed/2viK_LeoT4M" width="100%" height="100%" frameborder="0" allow="accelerometer; autoplay; encrypted-media; gyroscope; picture-in-picture" allowfullscreen style="display: block; margin: 0px auto; position: absolute; top: 0; left: 0;"></iframe></p>

### Code

I've [shared my code on GitHub](https://github.com/thedroidgeek/youtube-cast-automation-api) - it's a python script with a micro API that needs to be exposed to the internet, to then be linked to the Google Assistant through IFTTT, as previously explained - the details on how to do so as well as the API documentation can be found on the README of the repository.

### Potential future plans

Since I'm currently running my little server on a Raspberry Pi anyway, I might soon check out [Home Assistant](https://www.home-assistant.io/), so I can perhaps port my code to it, and potentially get into more home automation stuff - so I *might* diversify my future posts with more of such content as well, pending positive feedback.

See you in 2 years! /s

"Hey Google, publish blog post." &#x1F602;&#x1F44C;&#x1F4AF;&#x1F308;