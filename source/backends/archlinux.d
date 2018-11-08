module backends.archlinux;

import db;
import utils.vercmp;

ProcessedVersion[] getArchlinuxVersion(ref VersionInfo info) {
	import vibe.inet.urltransfer : download;
	import vibe.stream.operations : readAllUTF8, InputStream;
	import vibe.data.json;

	try {
		string data;
		download(info.url, (scope InputStream res) { data = res.readAllUTF8(); });
		if (!data.length)
			throw new Exception("Data is empty!");

		Json archInfo = data.parseJsonString;

		// Ignore epoch as this one is arch specific
		// Ignore release as this one is also arch specific
		// archInfo["epoch"].integer.text
		// archInfo["pkgrel"].str
		return [ProcessedVersion(Version(null, archInfo["pkgver"].get!string, null), Bson.emptyObject)];
	} catch (Exception e) {
		import std.format : format;

		logError("Exception: %s", e);
	}
	return null;
}
