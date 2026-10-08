import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import tempfile
import time
import sys
import urllib.request

VIDEO_SUFFIXES = {'.mkv', '.mp4', '.m4v', '.avi', '.mov', '.ts', '.m2ts', '.webm'}


def write_atomic(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', dir=path.parent, delete=False) as output:
        json.dump(value, output, ensure_ascii=False, indent=2)
        output.write('\n')
        temporary = output.name
    os.replace(temporary, path)


def refresh(section_id):
    preferences = plistlib.loads((Path.home() / 'Library/Preferences/com.plexapp.plexmediaserver.plist').read_bytes())
    request = urllib.request.Request('http://127.0.0.1:32400/library/sections/' + section_id + '/refresh', headers={'X-Plex-Token': preferences['PlexOnlineToken']})
    with urllib.request.urlopen(request, timeout=30) as response:
        return response.status


def update(config_path, trigger_refresh=True):
    config = json.loads(config_path.read_text())
    mappings = []
    errors = []
    changed = set()
    for library in config['libraries']:
        destination = Path(library['destination'])
        for rule in library.get('rules', []):
            source_root = Path(rule['source'])
            if not source_root.is_dir():
                errors.append({'source': str(source_root), 'reason': 'source-unavailable'})
                continue
            def walk_error(error):
                errors.append({'source': str(source_root), 'reason': type(error).__name__, 'errno': error.errno, 'message': error.strerror, 'filename': error.filename, 'operation': 'os.walk/scandir'})
            for folder, directories, files in os.walk(source_root, onerror=walk_error):
                for name in files:
                    source = Path(folder) / name
                    if source.suffix.lower() not in VIDEO_SUFFIXES:
                        continue
                    match = re.search(r'第\s*(\d+)\s*[话集]', source.stem)
                    if not match:
                        continue
                    episode = int(match.group(1))
                    season = rule.get('season', 1)
                    series = rule.get('series', source_root.name)
                    target = destination / series / ('Season %02d' % season) / ('%s - S%02dE%03d - %s' % (series, season, episode, source.name))
                    target.parent.mkdir(parents=True, exist_ok=True)
                    if target.is_symlink():
                        if os.readlink(target) != str(source):
                            errors.append({'source': str(source), 'reason': 'existing-link-target-differs'})
                            continue
                    elif target.exists():
                        errors.append({'source': str(source), 'reason': 'existing-non-link'})
                        continue
                    else:
                        target.symlink_to(source)
                        changed.add(library['sectionID'])
                    mappings.append({'source': str(source), 'link': str(target), 'season': season, 'episode': episode, 'sectionID': library['sectionID']})
    refreshed = []
    if trigger_refresh:
        for section_id in sorted(changed):
            try:
                refreshed.append({'sectionID': section_id, 'status': refresh(section_id)})
            except Exception as error:
                errors.append({'sectionID': section_id, 'reason': type(error).__name__})
    receipt = {'program': sys.executable, 'invocation': sys.argv, 'capturedAt': time.time(), 'config': str(config_path), 'mappings': mappings, 'changedSections': sorted(changed), 'refreshed': refreshed, 'errors': errors}
    write_atomic(config_path.with_name('normalized-media-receipt.json'), receipt)
    print(json.dumps({'links': len(mappings), 'changedSections': sorted(changed), 'refreshed': refreshed, 'errors': errors}, ensure_ascii=False))
    return receipt


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', type=Path, required=True)
    parser.add_argument('--no-refresh', action='store_true')
    arguments = parser.parse_args()
    result = update(arguments.config, not arguments.no_refresh)
    if result['errors']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
