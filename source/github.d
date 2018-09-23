module github;

import db;
import vercmp;

// feed/updated When tags where last changed

//TODO: return range
Version[] getGithubVersions(ref Project project) {
	import dxml.parser;
	import std.file : readText;

	string[] output;

	if (!project.githubName)
		return [Version()];

	// project.githubURL ~ "/releases.atom"
	// https://github.com/dlang/dmd/releases.atom;
	auto releases = parseXML(readText("cache/" ~ project.githubName ~ "/releases.atom"));
	assert(!releases.empty, project.name ~ ": File is empty");
	releases = releases.skipToPath("entry/title/");
	assert(!releases.empty, project.name ~ ": Could not find entry/title/");

	// TODO: Will it be sorted already?
	// TODO: Add getLatestVersion?

	while (!releases.empty) {
		import std.format;
		import std.stdio;

		assert(releases.front.type == EntityType.elementStart, format!"releases.front.type == %s"(releases.front.type));
		releases.popFront();
		assert(releases.front.type == EntityType.text, format!"releases.front.type == %s"(releases.front.type));
		output ~= releases.front.text;
		//writefln!"[%s] Found version: %s"(project.name, releases.front.text);
		releases = releases.skipToPath("../../../entry/title/");
	}

	import std.algorithm : map;
	import std.array : array;

	// TODO: Remove (optionally) beta and rc releases
	return output.map!getVersion
		.map!(v => Version(null, v.version_, v.release))
		.array;
}
