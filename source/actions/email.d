module actions.email;
import std.format;
import vibe.core.log;
import db;
import backends.github;

enum string siteLocation = "http://0.0.0.0:4000/";

void sendActivationEmail(string username, string email, uint code) {
	string emailData = format!`To: %2$s
From: me@vild.io
Subject: Activation code for Github Release Notififer

Hi, %1$s!

Your activation code is: %4$08X

Or you can follow this link: %3$sactivate?username=%1$s&code=%4$08X

---

Github Release Notifier
%3$s
`(username, email, siteLocation, code);

	logInfo(emailData);
}

void sendNewReleaseEmail(string username, string email, string projectName, GitHubVersion newRelease) {
	string emailData = format!`To: %2$s
From: me@vild.io
Subject: New release for %4$s - Github Release Notifier

Hi, %1$s!

%4$s have released '%5$s'.

Release info:
\tSemver: %6$s
\tSHA1:   %7$s

---

Github Release Notifier
%3$s
`(username, email, siteLocation, projectName, newRelease.name, newRelease.version_, newRelease.sha);

	logInfo(emailData);
}
