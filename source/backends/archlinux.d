module backends.archlinux;

import db;
import utils.vercmp;

Version getArchlinuxVersion(ref Project project) {
	import vibe.data.json;
	import std.file : readText;
	import std.conv : text;

	if (!project.archlinuxName)
		return Version();

	// project.archlinuxNameURL ~ "/json/"
	// https://www.archlinux.org/packages/community/x86_64/dmd/json/
	// readText("cache/" ~ project.githubName ~ "/arch.json")

	Json archInfo = parseJsonString(cast(string)VersionFile.findById(project.archlinuxFile).data);

	// Ignore epoch as this one is arch specific
	// Ignore release as this one is also arch specific
	// archInfo["epoch"].integer.text
	// archInfo["pkgrel"].str
	return Version(null, archInfo["pkgver"].get!string, null);
}
