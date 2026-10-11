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
import urllib.parse

VIDEO_SUFFIXES = {'.mkv', '.mp4', '.m4v', '.avi', '.mov', '.ts', '.m2ts', '.webm'}


def write_atomic(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', dir=path.parent, delete=False) as output:
        json.dump(value, output, ensure_ascii=False, indent=2)
        output.write('\n')
        temporary = output.name
    os.replace(temporary, path)


def plex_request(path, params=None, method='GET'):
    preferences = plistlib.loads((Path.home() / 'Library/Preferences/com.plexapp.plexmediaserver.plist').read_bytes())
    url = 'http://127.0.0.1:32400' + path
    if params:
        url += '?' + urllib.parse.urlencode(params)
    request = urllib.request.Request(url, method=method, headers={'X-Plex-Token': preferences['PlexOnlineToken'], 'Accept': 'application/json'})
    with urllib.request.urlopen(request, timeout=30) as response:
        body = response.read()
        return response.status, json.loads(body) if body else None


def refresh(section_id):
    return plex_request('/library/sections/' + section_id + '/refresh')[0]


def apply_ordering(config, mappings):
    desired = {str(Path(x['link']).parent.parent): x['sectionID'] for x in mappings if x.get('ordering') == 'absolute'}
    if not desired:
        return []
    series_ids = set()
    for section_id in set(desired.values()):
        start = 0
        while True:
            _, response = plex_request('/library/sections/' + section_id + '/all', {'type': 4, 'X-Plex-Container-Start': start, 'X-Plex-Container-Size': 500})
            page = response['MediaContainer']
            items = page.get('Metadata', [])
            for item in items:
                for media in item.get('Media', []):
                    for part in media.get('Part', []):
                        if any(part.get('file', '').startswith(root + '/') for root in desired):
                            series_ids.add(item['grandparentRatingKey'])
            start += len(items)
            if start >= page.get('totalSize', page.get('size', 0)) or not items:
                break
    result = []
    for series_id in sorted(series_ids):
        _, detail = plex_request('/library/metadata/' + series_id, {'includePreferences': 1})
        settings = detail['MediaContainer']['Metadata'][0].get('Preferences', {}).get('Setting', [])
        value = next((x.get('value') for x in settings if x['id'] == 'showOrdering'), None)
        if value != 'absolute':
            plex_request('/library/metadata/' + series_id + '/prefs', {'showOrdering': 'absolute'}, 'PUT')
            _, detail = plex_request('/library/metadata/' + series_id, {'includePreferences': 1})
            settings = detail['MediaContainer']['Metadata'][0].get('Preferences', {}).get('Setting', [])
            value = next((x.get('value') for x in settings if x['id'] == 'showOrdering'), None)
        result.append({'seriesID': series_id, 'ordering': value})
    return result


def episode_number(stem, mode):
    chinese = re.search(r'第\s*(\d+)\s*[话集]', stem)
    if chinese:
        return int(chinese.group(1))
    if mode == 'chinese':
        return None
    numbered = re.search(r'(?i)S\d+E(\d+)', stem)
    if numbered:
        return int(numbered.group(1))
    bracketed = re.search(r"\[(\d+)(?:['’])?\]", stem)
    if bracketed:
        return int(bracketed.group(1))
    trailing = re.search(r' - (\d{1,3})(?: (?:RAW|END)\b|$)', stem)
    return int(trailing.group(1)) if trailing else None


def primary_files(section_ids):
    paths = set()
    def collect(items):
        for item in items:
            if item.get('deletedAt'):
                continue
            for media in item.get('Media', []):
                if media.get('deletedAt'):
                    continue
                for part in media.get('Part', []):
                    if part.get('deletedAt'):
                        continue
                    if part.get('file'):
                        paths.add(str(Path(part['file']).resolve()))
            collect(item.get('Extras', {}).get('Metadata', []))
    for section_id in section_ids:
        for item_type in [4, 12]:
            start = 0
            while True:
                _, response = plex_request('/library/sections/' + section_id + '/all', {'type': item_type, 'includeExtras': 1, 'X-Plex-Container-Start': start, 'X-Plex-Container-Size': 500})
                page = response['MediaContainer']
                items = page.get('Metadata', [])
                collect(items)
                start += len(items)
                if start >= page.get('totalSize', page.get('size', 0)) or not items:
                    break
    return paths


def update(config_path, trigger_refresh=True):
    config = json.loads(config_path.read_text())
    mappings = []
    errors = []
    changed = set()
    unavailable = set()
    for library in config['libraries']:
        destination = Path(library['destination'])
        if library.get('sourceView'):
            view = Path(library['sourceView'])
            root = Path(library['sourceRoot'])
            view.mkdir(parents=True, exist_ok=True)
            try:
                sources = list(root.iterdir())
                for name in library.get('excludedDirectories', []):
                    target = view / name
                    if target.is_symlink():
                        target.unlink()
                        changed.add(library['sectionID'])
                for source in sources:
                    if source.name in library.get('excludedDirectories', []):
                        continue
                    target = view / source.name
                    if target.is_symlink():
                        if os.readlink(target) != str(source):
                            errors.append({'source': str(source), 'reason': 'existing-view-link-target-differs'})
                    elif target.exists():
                        errors.append({'source': str(source), 'reason': 'existing-view-non-link'})
                    else:
                        target.symlink_to(source)
                        changed.add(library['sectionID'])
            except OSError as error:
                errors.append({'source': str(root), 'reason': type(error).__name__, 'errno': error.errno, 'message': error.strerror})
                unavailable.add(library['sectionID'])
                continue
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
                    mode = rule.get('mode', 'chinese')
                    if rule.get('include') and not re.search(rule['include'], source.name, re.IGNORECASE):
                        continue
                    if rule.get('exclude') and re.search(rule['exclude'], source.name, re.IGNORECASE):
                        continue
                    series = rule.get('series', source_root.name)
                    if mode in ['extras', 'videos']:
                        episode = None
                        season = None
                        target = destination / series / 'Other' / source.name if mode == 'extras' else destination / series / source.stem / source.name
                    else:
                        episode = episode_number(source.stem, mode)
                        if episode is None:
                            continue
                        if mode == 'seasoned':
                            named_season = re.search(r'(?i)S(\d+)E\d+', source.stem)
                            folders = [re.fullmatch(r'(?i)Season\s+(\d+)', x) for x in source.relative_to(source_root).parts[:-1]]
                            folder_seasons = [int(x.group(1)) for x in folders if x]
                            if named_season:
                                season = int(named_season.group(1))
                            elif folder_seasons:
                                season = folder_seasons[-1]
                            else:
                                continue
                        else:
                            season = 1 if mode == 'absolute' else rule.get('season', 1)
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
                    mappings.append({'source': str(source), 'link': str(target), 'season': season, 'episode': episode, 'sectionID': library['sectionID'], 'mode': mode, 'ordering': 'absolute' if mode == 'absolute' else None})
    previous_file = config_path.with_name('normalized-media-receipt.json')
    previous_receipt = json.loads(previous_file.read_text()) if previous_file.exists() else {}
    previous = previous_receipt.get('mappings', [])
    for library in config['libraries']:
        for fallback in library.get('fallbackSources', []):
            root = Path(fallback['source'])
            try:
                files = []
                def fail_walk(error):
                    raise error
                for folder, _, names in os.walk(root, onerror=fail_walk):
                    files.extend(Path(folder) / name for name in names if Path(name).suffix.lower() in VIDEO_SUFFIXES)
                if not root.is_dir():
                    raise FileNotFoundError(str(root))
                covered = primary_files(fallback['primarySectionIDs'])
                covered.update(str(Path(x['source']).resolve()) for x in mappings)
            except Exception as error:
                errors.append({'source': str(root), 'operation': 'fallback-inventory', 'reason': type(error).__name__, 'errno': getattr(error, 'errno', None)})
                mappings.extend(x for x in previous if x.get('mode') == 'fallback' and x['sectionID'] == library['sectionID'])
                unavailable.add(library['sectionID'])
                continue
            for entry in previous:
                if entry.get('mode') == 'fallback' and entry['sectionID'] == library['sectionID'] and str(Path(entry['source']).resolve()) in covered:
                    target = Path(entry['link'])
                    if target.is_symlink() and os.readlink(target) == entry['source']:
                        target.unlink()
                        changed.add(library['sectionID'])
            for source in files:
                if str(source.resolve()) in covered:
                    continue
                relative = source.relative_to(root)
                target = Path(library['destination']) / 'Unclassified' / relative.parent / source.stem / source.name
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
                mappings.append({'source': str(source), 'link': str(target), 'season': None, 'episode': None, 'sectionID': library['sectionID'], 'mode': 'fallback', 'ordering': None})
    refreshed = []
    if trigger_refresh:
        for section_id in sorted(changed - unavailable):
            try:
                refreshed.append({'sectionID': section_id, 'status': refresh(section_id)})
            except Exception as error:
                errors.append({'sectionID': section_id, 'reason': type(error).__name__})
    ordering = previous_receipt.get('absoluteOrdering', [])
    if trigger_refresh:
        try:
            ordering = apply_ordering(config, mappings)
        except Exception as error:
            errors.append({'operation': 'apply-absolute-ordering', 'reason': type(error).__name__})
    receipt = {'absoluteOrdering': ordering, 'program': sys.executable, 'invocation': sys.argv, 'capturedAt': time.time(), 'config': str(config_path), 'mappings': mappings, 'changedSections': sorted(changed), 'refreshed': refreshed, 'errors': errors}
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
