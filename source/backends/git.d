module backends.git;

import db;
import utils.vercmp;
import vibe.data.json;

ProcessedVersion[] getGitVersions(ref VersionInfo info) {
	import std.process : execute, Config;
	import std.algorithm.mutation : remove;
	import std.algorithm.sorting : sort;
	import std.algorithm : splitter, startsWith;
	import std.string : indexOf, lastIndexOf;
	import std.array : array;

	auto output = execute(["git", "ls-remote", "-t", "-q", "--exit-code", info.url], ["GIT_TERMINAL_PROMPT" : "0"], Config.newEnv);
	if (output.status == 2)
		return [ProcessedVersion()];
	else if (output.status != 0)
		return null;

	string[string] tagMap;
	foreach (string line; output.output.splitter('\n')) {
		ptrdiff_t middle = line.indexOf('\t');
		if (middle == -1)
			continue;

		string sha = line[0 .. middle];
		string tag = line[middle + 1 .. $];
		if (!tag.startsWith("refs/tags/")) // Invalid!?!?
			continue;

		tag = tag["refs/tags/".length .. $];

		// If the tag was a annotated tag, use the last one.
		// This is probably not correct if the tag points to another tag. Could be (easier) fixed by linking to libgit2,
		// and using their API.
		if (tag[$ - 1] == '}')
			tag = tag[0 .. tag.lastIndexOf('^')];

		tagMap[tag] = sha;
	}

	ProcessedVersion[] versions;
	versions.length = tagMap.length;
	size_t idx;
	foreach (string tag, string sha; tagMap) {
		with (versions[idx]) {
			version_ = getVersion(tag);

			extraData = Bson.emptyObject;
			extraData["name"] = tag;
			extraData["sha"] = sha;
		}
		idx++;
	}

	return versions.sort!"a.version_ > b.version_".array;
}
