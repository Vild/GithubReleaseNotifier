module email;
import std.format;
import vibe.core.log;

enum string siteLocation = "http://0.0.0.0:4000";

void sendActivationEmail(string username, string email, uint code) {
	string emailData = format!`To: %2$s
From: me@vild.io
Subject: Activation code for Github Release Notififer

Hi, %1$s!

Your activation code is: %3$08X

Or you can follow this link: %4$s/activate?username=%1$s&code=%3$08X

---

Github Release Notifier
`(username, email, code, siteLocation);

	logInfo(emailData);
}
