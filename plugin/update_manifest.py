"""Adds a released plugin build to plugin/manifest.json (the Jellyfin plugin repository file).

Usage: python plugin/update_manifest.py <manifest> <version> <targetAbi> <zip> <download-url> <changelog>
Run by .github/workflows/plugin.yml on a plugin-v* tag; safe to re-run (replaces the same version).
"""
import datetime, hashlib, json, sys

manifest_path, version, abi, zip_path, url, changelog = sys.argv[1:7]
with open(manifest_path, encoding="utf-8") as f:
    manifest = json.load(f)
plugin = manifest[0]
md5 = hashlib.md5(open(zip_path, "rb").read()).hexdigest()
entry = {
    "version": version,
    "changelog": changelog,
    "targetAbi": abi,
    "sourceUrl": url,
    "checksum": md5,
    "timestamp": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
}
versions = [v for v in plugin["versions"] if v["version"] != version]
versions.append(entry)
versions.sort(key=lambda v: [int(p) for p in v["version"].split(".")], reverse=True)
plugin["versions"] = versions
with open(manifest_path, "w", encoding="utf-8") as f:
    json.dump(manifest, f, indent=2)
    f.write("\n")
print(f"manifest: added {version} (targetAbi {abi}, md5 {md5})")
