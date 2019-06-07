---
layout: post
title: 1-click RCE with Skype Web Plugin and Qt apps
excerpt_separator:  <!--more-->
categories:
  - InfoSec
---

### Context


Earlier this year, I've heard that you could send links with custom URI schemes through Discord, that can trigger without the user's confirmation when using desktop clients.

I've been experimenting with URI schemes ever since, I wanted to see how far I can push it in terms of exploitability, and I've found that you could do all sort of fun things in windows - stuff like opening the action center or the task switcher, etc. But I have quickly lost interest however, since I've realized there was a bunch of filters that Discord has in place, likely due to various reports from researchers, that prevent a lot of the known 'malicious' scheme links from triggering (though I still don't understand Discord's decision of not simply using a whitelist for schemes instead of adding regex filters ¯&#92;&#95;(ツ)&#95;/¯).

A couple of months later, it hit the headlines that Electronic Arts' digital distribution platform, Origin, was found to be vulnerable to an RCE through a URI scheme. This was due to an AngularJS template injection, that was met with some bad implementation that exposed Qt's common desktop services to JavaScript - more on this [here](https://zeropwn.github.io/2019-05-13-xss-to-rce/){:target="_blank"}{:rel="noopener noreferrer"}.

A [second blog post](https://zeropwn.github.io/2019-05-22-fun-with-uri-handlers/){:target="_blank"}{:rel="noopener noreferrer"} from the same researcher emerged, a couple of days later, where he found another 'flaw' in Origin that can be leveraged for RCE, but unlike the first one, this one wasn't exactly new - it was merely Qt's plugin feature which can be abused with the right conditions to load arbitrary .dll files through SMB shares ...

Following that blog post, I've re-enumerated the URL protocols on my machine (using [this](https://github.com/ChiChou/LookForSchemes){:target="_blank"}{:rel="noopener noreferrer"}), and went back to fiddling with URI schemes once more, and soon enough, I was able to find an interesting attack vector ...


### Qt plugin injection


According to Wikipedia, Qt is a free and open-source widget toolkit for creating GUIs and cross-platform applications, and it seems to be used by quite a lot of apps - a simple explorer search for the Qt core module revealed at least 9 64-bit apps currently installed on my machine:

![](/assets/media/qtcoredll-explorer-search.png)

Most of the modern Qt apps you will find will support a `-platformpluginpath` commandline option, which specifies a path to start with while loading plugins. What's interesting here is the fact that SMB shares are also supported, which means one can load plugins remotely.

So the question here would be, how can we start a Qt app with this `-platformpluginpath` argument so we can have it load our malicious plugin?

Yes, you guessed that right, URI schemes. In order for us to be able to launch an app with our custom input in the commandline, it has to have a registered custom URI handler so we can launch it via a webpage and have the URI be sent as an argument, here's what that looks like on the registry:

![](/assets/media/fdm-regedit.png)
![](/assets/media/fdm-regedit2.png)

However, there's a slight problem with this approach (as explained in the second blog post I've mentionned earlier), and that's the fact that modern browsers tend to apply URL encoding to the URI, before the app gets executed, which reduces our chance of pulling off the argument injection, since in most cases we would need to inject a double-quote to break out of the URI argument.

This is where the Skype Web Plugin comes to play ...


### Skype Web Plugin


When Skype for Web first launched, you could use Skype for instant messaging and share multimedia files, but not as a VoIP tool. To make voice and video calls in most supported browsers, people had to install a plugin.

Doing a quick search online revealed the last available version of the plugin was 7.32.6.278, which was released somewhere in 2016, but is still obtainable via their official CDN: [https://swx.cdn.skype.com/plugin/7.32.6.278/SkypeWebPlugin.msi](https://swx.cdn.skype.com/plugin/7.32.6.278/SkypeWebPlugin.msi){:target="_blank"}{:rel="noopener noreferrer"}

After Microsoft introduced plugin-free Skype for Web for their supported browsers, they ditched the plugin and dropped support for Internet Explorer. However, the plugin remains available in systems where previously installed, with the only way to get rid of it being a manual uninstall.

The 'Skype Web Plugin' registers a custom URI handler: `swx`, which launches `SkypeShell.exe`, which is what looks like to be some sort of Internet Explorer shell, which means that it uses IE's rendering engine (mshtml.dll) to open webpages.

To my surpise, this thing will open any HTTP URL, all you need to do is replace `http(s)` with `swx`, and you have a clickable link that forcefully renders your website using mshtml.dll, but here's the real problem ...

First of all, protected mode is off by default, so this may potentially allow for more attack vectors that I'm currently not aware of, since I'm not familiar with what protected mode exactly even does, but this certainly doesn't sound good.

![](/assets/media/skypeshell-no-protected-mode.png)

Secondly (which is what's more relevant to us), I can load any link with a custom URI from within the shell without having the user to confirm or know anything.

For reference, here's what trying to exploit a Qt app using plugin injection would prompt for, when running IE normally:

![](/assets/media/ie-scheme-prompt.png)

So not only can we successfully inject arguments regardless of what browser the victim uses, we can also spawn a dosen of apps through URIs simultaneously.


### The Proof of Concept


Now that we've got a clear idea of the attack vector we will be using, we'll start on the implementation.

The first thing we would need to do is find target Qt apps to exploit, which are essentially apps that allow loading plugins (nearly all of them do), and that have a registered URI handler.

I've found 2 of them already installed on my machine:

- [Free Download Manager](//freedownloadmanager.org){:target="_blank"}{:rel="noopener noreferrer"} - The 2nd Google result when searching 'download manager'.
- And [Origin](//origin.com){:target="_blank"}{:rel="noopener noreferrer"}, of course.

I've tried to find more apps that meet the 2 conditions to verify my claims, and sure enough with little to no effort I was able to find the [Transmission](https://github.com/transmission/transmission){:target="_blank"}{:rel="noopener noreferrer"} torrent client, which I'm also adding to the list.

Like I said earlier, this is not exactly a new thing, 2 months ago someone wrote [this article](https://www.zerodayinitiative.com/blog/2019/4/3/loading-up-a-pair-of-qt-bugs-detailing-cve-2019-1636-and-cve-2019-6739){:target="_blank"}{:rel="noopener noreferrer"} explaining how Malwarebytes and Cisco Webex Teams (both of which are programs I've used before) were found to be vulnerable to this attack, but what's interesting here, is the stealthiness and reliability that we can accomplish with the help of the Skype Web Plugin ...

So I started by simply spamming an .html file with iframes that have `calculator://` as a src attribute:

```html
<iframe src='calculator://' height="0" frameborder="0"></iframe>
<iframe src='calculator://' height="0" frameborder="0"></iframe>
...
```

And as expected, I soon started to hear my CPU fan ...

![](/assets/media/calcspam.gif)

So at the very least this can be used for DoS by spam launching resource heavy apps, so far so good.

Now on to the code execution...

I've fired up Visual Studio and made a quick DLL that shows a MessageBox on attach with the process file name as a message.

To make our .dll loadable by Qt, we have to:
- **Add a `.qtmetad` section with valid plugin metadata:**
We make VS generate an empty one that we'll fill out manually with a hex editor using content from the original plugin.
- **Find a plugin we can override:**
There's this one called the Windows Integration Plugin (qwindows.dll) which all apps seem to require in order to run on Windows.

To make this stealthy, I've added an `ExitProcess()` right after the DLL is done executing to prevent the target app from showing up, so as of this stage there's no visible interruption (besides the Skype shell) and the user won't notice anything.

Now all that's left for us to have is an SMB share that will host our malicous plugins.

Here's a detailed video of the PoC in action, from crafting the .dll files to the MessageBox on the 3 apps:

<p style="position: relative; padding: 30px 0px 57% 0px; height: 0; overflow: hidden;"><iframe src="https://www.youtube.com/embed/xVZU-2Y0Pzc" width="100%" height="100%" frameborder="0" allow="accelerometer; autoplay; encrypted-media; gyroscope; picture-in-picture" allowfullscreen style="display: block; margin: 0px auto; position: absolute; top: 0; left: 0;"></iframe></p>


### DoS Bonus


I've come across this URI `ms-cxh-full://` that seems to be the fullscreen version of `ms-cxh://` which is something used in Microsoft account setup, but what's interesting is that this one can cause a black screen that can't be dismissed, forcing the user to sign out/reboot.
[⚠️ Try at your own risk ⚠️](ms-cxh-full://)
