module vercmp;

struct Version {
	string epoch;
	string version_;
	string release;

	bool opCast(T : bool)() {
		return epoch.length || version_.length || release.length;
	}

	string toString() const {
		import std.format : format;

		return format!"%s%s%s%s%s"(epoch, epoch.length ? ":" : "", version_, release.length ? "-" : "", release);
	}

	int opCmp(ref const(Version) other) const {
		int cmp(string a, string b) {
			if (a == b)
				return 0;

			while (a.length && b.length) {
				import std.ascii : isDigit, isAlpha, isAlphaNum;

				while (a.length && !a[0].isAlphaNum && a[0] != '~')
					a = a[1 .. $];
				while (b.length && !b[0].isAlphaNum && b[0] != '~')
					b = b[1 .. $];

				if ((a.length && a[0] == '~') || (b.length && b[0] == '~')) {
					if (a[0] != '~')
						return 1;
					if (b[0] != '~')
						return -1;

					a = a[1 .. $];
					b = b[1 .. $];
					continue;
				}

				if (!a.length || !b.length)
					break;

				bool isDigitPart;
				string aPart, bPart;

				import std.algorithm : countUntil, cmp;

				if (a[0].isDigit) {
					ptrdiff_t aCount = a.countUntil!(x => !x.isDigit);
					ptrdiff_t bCount = b.countUntil!(x => !x.isDigit);

					if (aCount == -1)
						aCount = a.length;
					if (bCount == -1)
						bCount = b.length;

					aPart = a[0 .. aCount];
					bPart = b[0 .. bCount];
					a = a[aCount .. $];
					b = b[bCount .. $];

					isDigitPart = true;
				} else if (a[0].isAlpha) {
					ptrdiff_t aCount = a.countUntil!(x => !x.isAlpha);
					ptrdiff_t bCount = b.countUntil!(x => !x.isAlpha);

					if (aCount == -1)
						aCount = a.length;
					if (bCount == -1)
						bCount = b.length;

					aPart = a[0 .. aCount];
					bPart = b[0 .. bCount];
					a = a[aCount .. $];
					b = b[bCount .. $];

					isDigitPart = false;
				}

				if (!a.length)
					return -1;
				if (!b.length)
					return isDigitPart ? 1 : -1;

				if (isDigitPart) {
					a = a[a.countUntil!(x => x != '0') .. $];
					b = b[b.countUntil!(x => x != '0') .. $];

					if (a.length > b.length)
						return 1;
					else if (a.length < b.length)
						return -1;
				}

				if (auto r = cmp(a, b))
					return r;
			}
			if (!a.length && !b.length)
				return 0;
			return a.length ? 1 : -1;
		}

		/*import std.stdio;

		writeln("Comparing ", this, " <=> ", other);
		writeln("\tcmp(epoch, other.epoch): ", cmp(epoch, other.epoch));
		writeln("\tcmp(version_, other.version_): ", cmp(version_, other.version_));
		writeln("\tcmp(release, other.release): ", cmp(release, other.release));*/

		int r = cmp(epoch, other.epoch);
		if (r)
			return r;
		r = cmp(version_, other.version_);
		if (r)
			return r;
		r = cmp(release, other.release);
		return r;
	}
}

// version format is '[epoch:]version[-release]'
Version getVersion(string ver) {
	import std.regex : matchFirst, ctRegex;

	Version v;

	if (ver.length && ver[0] == 'v')
		ver = ver[1 .. $];

	/***
		^               = Start of line
		(?:[\w]*[\s]+)? = Optionally, find alphaNums{0,∞} that ends with whitespace characters{1,∞}. DISCARD
		(?:([\w.-]+):)? = Optionally, find a epoch (everything before ':'), and discard the ':'
		([\w.]+)        = Find the version
		(?:-([\w.]+))?  = Optionally, find a release (everything after '-'), and discard the '-'
		$               = End of line
	*/
	auto match = ver.matchFirst(ctRegex!`^(?:[\w]*[\s]+)?(?:([\w.-]+):)?([\w.]+)(?:-([\w.]+))?`);
	v.epoch = match[1] ? match[1] : "0";
	v.version_ = match[2];
	v.release = match[3];

	return v;
}
