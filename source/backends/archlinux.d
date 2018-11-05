module backends.archlinux;

import db;
import utils.vercmp;

ProcessedVersion[] getArchlinuxVersion(ref VersionInfo info) {
	import vibe.data.json;
	import std.file : readText;
	import std.conv : text;
	import std.net.curl : get;
	import std.exception : assumeUnique;

	scope (failure)
		return null;

	string data = assumeUnique(get(info.url));
	Json archInfo = data.parseJsonString;

	// Ignore epoch as this one is arch specific
	// Ignore release as this one is also arch specific
	// archInfo["epoch"].integer.text
	// archInfo["pkgrel"].str
	return [ProcessedVersion(Version(null, archInfo["pkgver"].get!string, null), Bson.emptyObject)];
}
