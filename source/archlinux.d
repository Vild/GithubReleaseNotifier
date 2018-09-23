module archlinux;

import db;
import vercmp;

Version getArchlinuxVersion(ref Project project) {
	import std.json;
	import std.file : readText;
	import std.conv : text;

	if (!project.archlinuxName)
		return Version();

	// project.archlinuxNameURL ~ "/json/"
	// https://www.archlinux.org/packages/community/x86_64/dmd/json/
	JSONValue archInfo = parseJSON(readText("cache/" ~ project.githubName ~ "/arch.json"));

	// Ignore epoch as this one is arch specific
	// Ignore release as this one is also arch specific
	// archInfo["epoch"].integer.text
	// archInfo["pkgrel"].str
	return Version(null, archInfo["pkgver"].str, null);
}
