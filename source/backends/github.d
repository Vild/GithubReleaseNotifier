module backends.github;

import db;
import utils.vercmp;

struct GitHubVersion {
	Version version_;
	string name;
	string sha;
}

/*
"name": "v2.083.0-beta.1",
"zipball_url": "https://api.github.com/repos/dlang/dmd/zipball/v2.083.0-beta.1",
"tarball_url": "https://api.github.com/repos/dlang/dmd/tarball/v2.083.0-beta.1",
"commit": {
	"sha": "ba333c82623b928dbc7b832cfadfc3b036725cda",
	"url": "https://api.github.com/repos/dlang/dmd/commits/ba333c82623b928dbc7b832cfadfc3b036725cda"
},
"node_id": "MDM6UmVmMTI1NzA3MDp2Mi4wODMuMC1iZXRhLjE="
*/

GitHubVersion[] getGitHubVersions(ref Project project, bool ignorePreRelease) {
	import dxml.parser;
	import std.file : readText;
	import vibe.data.json;
	import std.algorithm.mutation : remove;
	import std.algorithm.sorting : sort;

	string[] output;

	if (!project.githubName)
		return [GitHubVersion()];

	Json githubInfo = parseJsonString(cast(string)GitHubVersionFile.findById(project.githubFile).data);
	GitHubVersion[] versions;
	versions.length = githubInfo.length;

	foreach (size_t idx, Json tag; githubInfo)
		versions[idx] = GitHubVersion(getVersion(tag["name"].get!string), tag["name"].get!string, tag["commit"]["sha"].get!string);

	foreach (GitHubVersion v; versions)
		v.version_.epoch = null;

	// TODO: Add option for this (re-add beta and rc releases)
	if (ignorePreRelease)
		versions = versions.remove!"a.version_.release.length";

	return versions.sort!"a.version_ > b.version_".array;
}
