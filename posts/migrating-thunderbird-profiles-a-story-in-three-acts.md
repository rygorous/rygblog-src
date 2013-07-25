-title=Migrating Thunderbird profiles: A story in three acts
-time=2011-09-30 09:32:54


### Prologue

This is a slight bit of a departure from the usual themes in this blog, but I thought it was interesting enough to write it up anyway. It also makes for a nice break from the Trip through the Graphics Pipeline series that's been dominating this blog recently \(conclusion coming Real Soon Now \- and there's 4 other queued up articles in various stages of completion, we'll see what comes of that\). 

### Act I

*in which the protagonist fails at performing a seemingly simple task.*

My laptop was getting a bit long in the tooth \- the way that these things go. Battery charges don't last as long as they used to \- I'm used to that. WiFi grows a bit erratic \- well, whatever, it never was that stable anyway. Windows getting a bit sluggish? Happens. Fans don't work properly anymore so CPU stays permanently down\-clocked and I can't even watch videos without stutters anymore, HD starts making slightly worrying noises, Windows Update gets stuck trying to install one patch on every single shutdown and crashes? Okay, so maybe it was time to buy a new laptop after all. Which I promptly did a few weeks ago.

Now, the way new hardware usually goes for me is I buy it, maybe put it together, make sure that it works properly, then don't do much with it for a while, and finally decide to spend a weekend to migrating data over from the predecessor machine. Now, that "don't do much with it for a while" phase can last for a long time \- when I first got a 64\-bit machine, I set it up then didn't touch it again for the next 3 months; in this case it wasn't that extreme, but it still took me over a week until I started setting up the new machine; that was last weekend.

For the most part, this was exactly as boring as you would expect \- installing a bunch of programs, copying over data, the works. However, it got a bit more interesting when I tried to transfer my Thunderbird profile \(including mails\) over from my previous machine. If you've never done this, it's an "interesting" user experience, because to this date the Thunderbird authors seem to think that this problem is sufficiently rare and esoteric that it doesn't need to be solved by their mail client directly \(...no comment\). The unofficial way to do this is to either locate and copy your profile directory manually, or to use [MozBackup](http://mozbackup.jasnapaka.com/), a third\-party tool that locates the profile directory for you and packs up all its contents into one file that can then be transferred to \(and restored on\) the target machine. I picked the latter option, because the Thunderbird profile is spread across multiple directories \(...why?!?\) and I vaguely remembered that the last time I had tried to do this manually, I ran into some weird issue where part of my profile wasn't where I expected it to be. So I figured, let the specialized tool deal with it this time!

Given the title of this post and the fact that we're still in Act I, it shouldn't come as much of a surprise that this did not, in fact, work properly. Well, to be fair, it *mostly* worked \- my main private mail account, all its associated filter rules, and two other "legacy" POP3 accounts that I check maybe once every 6 months came over just fine. However, my work email account did not work properly. It was added, the screen/user names as well as the server settings were all correct, but Thunderbird just wouldn't display any of its folders no matter what I did. Well, since this was an IMAP account, I figured I might as well delete it and set it up anew \- all the mails were on the server anyway. So that's what I did \- only to realize that I wasn't sure about the password anymore; I had last entered it over a year ago. I did have it written down on a post\-it in my office when I started at RAD, but I've switched offices two times since then, and that post\-it was nowhere to be found. Anyway, I created a new mail account for my work address, entered the password the way I remembered and... nothing happened. Absolutely nothing. Again, no folders, no nothing. Not even signs of communication with the server.

I figured that something must be going wrong with the password authentication, but since Thunderbird didn't pop up any error messages, I wasn't sure where to start looking. And after a day spent setting up a machine, I didn't feel like debugging either. So I decided to leave it alone for awhile.

### Act II

*in which passwords are changed and bugs in the mail admin interface are discovered.*

On Wednesday I decided that I should really get this resolved before the weekend, so I asked around whether we had the passwords written down somewhere \(and got the Only Right Answer: no, we didn't!\) and if not, whether my password could be reset to a new value \- it could, but only my boss had the necessary password for our mail system, so it took another day for the password change to happen, which was today.

It was a simple plan: Jeff \(my boss\) would just change my mail password and give me the new one.

Well, it was a partial success. Jeff indeed changed my password and gave me a new one \- except it didn't work. Some triple\-checking and experimenting later, I decided that he had probably made a typo in either the new password or the string he sent me. So I went to his office and told him so \- "no, I definitely gave you the right password!". He went to the mail admin interface, tried to log in with me username and the new password, and... it didn't work. First response: "okay, did I manage to mistype that the same way twice when I changed the password?". So he changed the password again to the intended value \- nope, didn't work this time either.

New theory: Since the new password was more like a passphrase and involved SeveralWordsInCamelCase, it was quite long; my old password had been 10 characters, whereas the new password might exceed whatever internal limit the system had. I'd had that suspicion before and tried several prefixes of the password with various lengths on my login attempts, but none of them worked either. But this time, Jeff changed the password to something shorter, and indeed, logging in worked fine now. Great \- evidently there *was* a limit on password length, but the admin interface didn't warn about it or produce any error \- it just changed the password anyway \(it's unclear what it changed it to\) and happily chugged along. Great.

Anyway, I could read my work mails at work again, which was good enough for the moment. As I discovered a bit later though, it did not fix the Thunderbird mail issues I was having; even with a password that I knew worked on my office PC \(using the exact same server settings and version of Thunderbird\), IMAP wouldn't work at all on my new laptop. And as the curtain falls for Act II, I leave you with one simple question to ponder: *What if Jeff had tried to use the long password for the admin account instead of mine?*

### Act III

*in which experiments are conducted and the terrible truth is revealed.*

When the password that I knew was right still failed in my Thunderbird setup, I knew that something deeper was wrong. So it was time to switch into experimentation mode: rename my profile directory so Thunderbird couldn't find it, uninstall Thunderbird, re\-install it, and set up the RAD email account on a fresh, pristine installation of Thunderbird.

And voilá, it worked just fine.

Okay, now I had a fresh IMAP account that worked. So I figured, hey, let MozBackup restore settings for my other accounts from the backed up profile again and I'm set, right? Wrong. MozBackup can't do that. It's all or nothing \- you can backup/restore a whole profile, but not individual accounts in it, and restoring overwrites everything in the profile include whatever new accounts you may have set up. Great.

Plan B: I still had the original backup file that I used to transfer the mails over to the new machine. MozBackup will not let you restore individual accounts, but it will let you select what *kind* of information to restore. I figured that something was wrong with the settings, so instead of restoring everything, I kept it to the bare bones \(just Emails and the Address Book\). Nope, even just restoring these two things alone, I could neither use the restored RAD IMAP account nor set up a new IMAP account.

I decided to check the error console. There was a bunch of error spew in there all right, but it was completely useless, consisting of a few hex values and a trace to some JavaScript function that also didn't prove helpful in determining what was going on. Googling for the error message turned up nothing interesting \- there was a reference to a bug in some old Thunderbird version, but it had \(according to the ticket anyway\) been fixed long ago, and indeed I can confirm that the patch in question had been applied, since *that was the code I was getting the error message from*. All I got from that line of investigation was that it was trying \(and failing\) to enumerate mail folders for that account \- yes, indeed, I could see that by myself.

Okay, Plan C: Go back to the original profile and try to figure out what's wrong by myself. I didn't really know where to start, so I just grepped for the mail server name in the main profile to directory to see where it would turn up.

First, I got a whole bunch of hits in a file called `panacea.dat`. So I looked at that file \- WTF? It was full of path names *from my old machine!* \(how to tell? The paths start with `C:\Dokumente und Einstellungen`, which is the German equivalent to the XP\-era `C:\Documents and Settings`; the new Laptop is running English Windows 7, and that path doesn't exist\). In fact, it was full of path names to mail folders for old mail accounts, some of which I deleted 6 years ago. Some googling later, I learn that `panacea.dat` is just a cache for the location of mail folders. So I should be able to just delete it, right? Well, rename it, anyway \- *never ever* randomly delete files in this kind of situation! And indeed, after restarting Thunderbird I was rewarded with a shiny, new, 17k `panacea.dat` \(instead of the old 77k one\) that only contained references to directories that actually existed on my machine. Progress! Sadly, it didn't solve the problem, though; my RAD account still wouldn't work.

Okay, what else showed up in the grep I did earlier? Next promising target was `prefs.js`. And, indeed: paydirt! First interesting thing I found in that file was this:

```
user_pref("mail.root.imap", "C:\\DOCUMENTS AND SETTINGS\\FG\\APPLICATION DATA\\Thunderbird\\Profiles\\Default User\\rtq40szi.slt\\ImapMail");
user_pref("mail.root.imap-rel", "[ProfD]../../../../../../DOCUMENTS AND SETTINGS/FG/APPLICATION DATA/Thunderbird/Profiles/Default User/rtq40szi.slt/ImapMail");
user_pref("mail.root.none", "C:\\DOCUMENTS AND SETTINGS\\FG\\APPLICATION DATA\\Thunderbird\\Profiles\\Default User\\rtq40szi.slt\\Mail");
user_pref("mail.root.none-rel", "[ProfD]../../../../../../DOCUMENTS AND SETTINGS/FG/APPLICATION DATA/Thunderbird/Profiles/Default User/rtq40szi.slt/Mail");
user_pref("mail.root.pop3", "C:\\DOCUMENTS AND SETTINGS\\FG\\APPLICATION DATA\\Thunderbird\\Profiles\\Default User\\rtq40szi.slt\\Mail");
user_pref("mail.root.pop3-rel", "[ProfD]Mail");
```

WTF? Absolute path names? And using the *English* version, of the path names, no less! Remember this profile came from a machine running a German Windows XP. More importantly, the relative version of the root for POP3 is set up correctly, whereas for "none" and IMAP, it's effectively an absolute path, and it means it'll try to use the "Documents and Settings" version even on the German Windows XP that was on the source machine. Also, `rtq40szi.slt` is not the unique ID for the profile on the source machine \- it used `8z9cx5rb.default`! What the hell was going on?

A bit later in the file, there were paths for the various identities. For reference, here are the corresponding paths for my main private mail address:

```
user_pref("mail.server.server1.directory", "C:\\Dokumente und Einstellungen\\fg\\Anwendungsdaten\\Thunderbird\\Profiles\\8z9cx5rb.default\\Mail\\mail.gmx.net");
user_pref("mail.server.server1.directory-rel", "[ProfD]Mail/mail.gmx.net");
```

Note that this time, the absolute directory actually exists on the source machine, it's using the right profile ID, and the relative path makes sense. Compare to the path for my work mail address:

```
user_pref("mail.server.server6.directory", "C:\\DOCUMENTS AND SETTINGS\\FG\\APPLICATION DATA\\Thunderbird\\Profiles\\Default User\\rtq40szi.slt\\ImapMail\\mail.radgametools.com");
user_pref("mail.server.server6.directory-rel", "[ProfD]../../../../../../DOCUMENTS AND SETTINGS/FG/APPLICATION DATA/Thunderbird/Profiles/Default User/rtq40szi.slt/ImapMail/mail.radgametools.com");
```

And another WTF \- this time it's using the English version of the directory name again, the wrong profile ID, and the relative path is completely screwed up again!

At that point I decided to double\-check on the source machine. And indeed, I did have `c:\DOCUMENTS AND SETTINGS\FG\...` \(all caps for some reason\) that contained exactly my work email identity and nothing else.

Once I figured that out, I just copied the contents of that profile directory into the main profile directory on my new laptop. I then fixed up all the paths in `prefs.js` \(read: I deleted the absolute path references and replaced the relative ones with sane values\). And tada \- now my work email account worked. Problem finally solved!

### Epilogue

Okay, so there's one unanswered question: How did the profile stuff get fucked up like that in the first place? To be honest, I'm not sure; I've been using Thunderbird since mid\-2004 \(that was before 1.0\) and migrated it between several machines over that time. However, I can guess: Even though I'm from Germany, I've been mostly using English Windows versions for a long time. All the SW I use on a daily basis comes in English, and using English SW on a German Windows results in things like Message Boxes with English text and German "Ja" / "Nein" \(Yes / No\) buttons. And we can't have that, can we? Right. So given the choice, I've been buying English versions of Windows for a long time. But sometimes you don't have a choice \- when buying my old laptop, for instance, which came with a German OEM version of Windows and had no option to change the language.

So when I originally moved the Thunderbird profile to my Laptop, it was from an English version of Windows. At that point, my profile had several POP3 accounts still in use, so the stored relative root path for POP3 accounts \(`[ProfD]Mail`\) worked. I did not, however, have an active IMAP account at that point in time \(I had deleted my University IMAP account some months earlier\). Thus my profile contained no "ImapMail" folder \- and since neither the absolute nor relative root path contained a valid directory name, Thunderbird apparently decided to trust the stored absolute path name and set the new relative path from it \(which is how the whole `../../../../../../DOCUMENTS AND SETTINGS` business got started\).

This didn't matter for the next one and a half years, during which I used no IMAP account. However, when I started at RAD last year, I added my work mail address as an IMAP account, at which point the `C:\DOCUMENTS AND SETTINGS` directory presumably got created on the German XP laptop. This being XP, you could still create directories at the root of the drive without admin privileges.

Now, the settings imported to the new laptop contained all the broken IMAP root directory settings from the profile \- but this being Windows 7, you can't just create a "Documents and Settings" in the root directory this time. So Thunderbird knew where it wanted to create its profile directory, but couldn't, and therefore it couldn't set up its mailbox files, and therefore I couldn't see any mails. Awesome.

What really pisses me off about this whole episode is that a\) Thunderbird doesn't complain when profile data is stored outside the profile root directory \(that should be a red flag right there!\), b\) Thunderbird stores absolute path names anywhere in the first place \(why?!?\), and c\) despite there having to be at least half a dozen failed system calls on the way there, the only actual error that gets reported in any visible fashion is from some stupid JavaScript frontend thing. And not only is that error message hidden in a place where an average user would probably never find it, it's also completely indecipherable even if you know where to look.