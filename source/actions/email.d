module actions.email;
import std.format;
import vibe.core.log;
import db;
import backends.git;

enum string siteLocation = "http://0.0.0.0:4000/";

bool sendActivationEmail(string username, string email, uint code) {
	scope (failure)
		return false;
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
	return true;
}

bool sendNewReleaseEmail(string username, string email, string projectName, ProcessedVersion newRelease) {
	scope (failure)
		return false;

	logDebug("newRelease: %s", newRelease);

	string emailData = format!`To: %2$s
From: me@vild.io
Subject: New release for %4$s - Github Release Notifier

Hi, %1$s!

%4$s have released '%5$s'.

Release info:
	Semver: %6$s
	SHA:    %7$s

---

Github Release Notifier
%3$s
`(username, email, siteLocation, projectName, newRelease.extraData["name"].get!string,
			newRelease.version_, newRelease.extraData["sha"].get!string);

	logInfo(emailData);
	return true;
}
