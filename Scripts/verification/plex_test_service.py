import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import time
import tempfile
import urllib.parse
import urllib.request
import unicodedata

REPOSITORY = Path(__file__).resolve().parents[2]
SCRATCH = REPOSITORY / 'tmp/archive/plex-setup'
CREDENTIALS = REPOSITORY / 'Tests/EmbyPackageTests/Fixtures/PlexServerCredentials.local.json'
APP = Path('/Applications/Plex Media Server.app')
MEDIA = Path.home() / 'Library/CloudStorage/EmbyMedia'
DATA = Path.home() / 'Library/Application Support/EnchronTestServices/Plex'
BASE = 'http://127.0.0.1:32400'


def credential():
    return plistlib.loads((Path.home() / 'Library/Preferences/com.plexapp.plexmediaserver.plist').read_bytes())['PlexOnlineToken']


def request(path, params=None, method='GET', raw=False, extra_headers=None):
    url = BASE + path
    if params:
        url += '?' + urllib.parse.urlencode(params, doseq=True)
    headers = {'X-Plex-Token': credential(), 'Accept': 'application/json', 'X-Plex-Client-Identifier': 'enchron-service-verification', 'X-Plex-Product': 'EnchronVerify', 'X-Plex-Version': '1.0', 'X-Plex-Device': 'Mac'}
    headers.update(extra_headers or {})
    with urllib.request.urlopen(urllib.request.Request(url, headers=headers, method=method), timeout=30) as response:
        body = response.read()
        if raw:
            return response.status, dict(response.headers), body
        return json.loads(body) if body else {}


def save(name, data):
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', dir=SCRATCH, prefix=name + '.', suffix='.tmp', delete=False) as output:
        output.write(json.dumps(data, ensure_ascii=False, indent=2) + '\n')
        temporary = output.name
    os.replace(temporary, SCRATCH / name)


def install():
    if not APP.exists():
        SCRATCH.mkdir(parents=True, exist_ok=True)
        with urllib.request.urlopen('https://plex.tv/api/downloads/5.json') as response:
            release = json.load(response)['computer']['MacOS']['releases'][0]
        archive = SCRATCH / 'PlexMediaServer.zip'
        urllib.request.urlretrieve(release['url'], archive)
        if hashlib.sha1(archive.read_bytes()).hexdigest() != release['checksum']:
            raise RuntimeError('Plex download checksum mismatch')
        unpacked = SCRATCH / 'unpacked'
        subprocess.run(['ditto', '-x', '-k', str(archive), str(unpacked)], check=True)
        subprocess.run(['ditto', str(unpacked / APP.name), str(APP)], check=True)
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(APP)], check=True)
    DATA.mkdir(parents=True, exist_ok=True)
    label = 'com.enchron.test-plex'
    launch = Path.home() / 'Library/LaunchAgents' / (label + '.plist')
    launch.parent.mkdir(parents=True, exist_ok=True)
    launch.write_bytes(plistlib.dumps({'Label': label, 'ProgramArguments': [str(APP / 'Contents/MacOS/Plex Media Server')], 'RunAtLoad': True, 'KeepAlive': True, 'StandardOutPath': str(DATA / 'server.stdout.log'), 'StandardErrorPath': str(DATA / 'server.stderr.log')}))
    domain = 'gui/' + str(os.getuid())
    loaded = subprocess.run(['launchctl', 'print', domain + '/' + label], capture_output=True).returncode == 0
    if not loaded:
        try:
            request('/identity')
        except Exception:
            subprocess.run(['launchctl', 'bootstrap', domain, str(launch)], check=True)
    deadline = time.monotonic() + 60
    while True:
        try:
            identity = request('/identity')['MediaContainer']
            if identity.get('claimed'):
                break
        except Exception:
            pass
        if time.monotonic() >= deadline:
            raise RuntimeError('Plex not ready or unclaimed; finish account setup at http://127.0.0.1:32400/web')
        time.sleep(1)
    payload = {'schema': 'enchron.plex-test-credentials.v1', 'address': 'http://Mac-mini.local:32400', 'token': credential(), 'serverID': identity['machineIdentifier']}
    CREDENTIALS.parent.mkdir(parents=True, exist_ok=True)
    CREDENTIALS.write_text(json.dumps(payload, indent=2) + '\n')
    os.chmod(CREDENTIALS, 0o600)
    request('/:/prefs', {'FriendlyName': 'Enchron Plex', 'autoEmptyTrash': 0, 'GenerateBIFBehavior': 'never', 'GenerateChapterThumbBehavior': 'never', 'FSEventLibraryUpdatesEnabled': 1, 'FSEventLibraryPartialScanEnabled': 1, 'ScheduledLibraryUpdatesEnabled': 1, 'ScheduledLibraryUpdateInterval': 3600}, method='PUT')
    print(json.dumps({'address': payload['address'], 'version': identity['version'], 'credentials': str(CREDENTIALS)}))


def emby_inventory():
    credentials = json.loads((REPOSITORY / 'Tests/EmbyPackageTests/Fixtures/EmbyServerCredentials.local.json').read_text())
    base = 'http://127.0.0.1:8096'
    headers = {'X-Emby-Authorization': 'MediaBrowser Client="EnchronPlexSync", Device="Mac", DeviceId="enchron-plex-sync", Version="1"', 'Content-Type': 'application/json'}
    payload = json.dumps({'Username': credentials['username'], 'Pw': credentials['password']}).encode()
    with urllib.request.urlopen(urllib.request.Request(base + '/Users/AuthenticateByName', data=payload, headers=headers), timeout=30) as response:
        authentication = json.load(response)
    headers['X-Emby-Token'] = authentication['AccessToken']
    def get(path, params=None):
        url = base + path
        if params:
            url += '?' + urllib.parse.urlencode(params)
        with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=30) as response:
            return json.load(response)
    folders = get('/Library/VirtualFolders')
    result = []
    for folder in folders:
        files = set()
        items = 0
        start = 0
        while True:
            page = get('/Users/' + authentication['User']['Id'] + '/Items', {'ParentId': folder['ItemId'], 'Recursive': 'true', 'IncludeItemTypes': 'Movie,Episode,Video,Audio,MusicVideo', 'Fields': 'Path,MediaSources', 'EnableImages': 'false', 'EnableUserData': 'false', 'StartIndex': start, 'Limit': 500})
            for item in page['Items']:
                sources = [x['Path'] for x in item.get('MediaSources', []) if x.get('Path')]
                for path in sources or [item.get('Path')]:
                    if path and path.startswith('/'):
                        files.add(unicodedata.normalize('NFC', os.path.normpath(path)))
                items += 1
            start += len(page['Items'])
            if start >= page['TotalRecordCount'] or not page['Items']:
                break
        result.append({'name': folder['Name'], 'collectionType': folder.get('CollectionType'), 'locations': folder['Locations'], 'items': items, 'files': sorted(files)})
    return {'capturedAt': time.time(), 'libraries': result, 'totalItems': sum(x['items'] for x in result), 'totalFiles': len({path for x in result for path in x['files']})}


def libraries(refresh=False):
    inventory = emby_inventory()
    if not (SCRATCH / 'full-sync-baseline.json').exists():
        save('full-sync-baseline.json', inventory)
    save('emby-full-inventory.json', inventory)
    sections = request('/library/sections')['MediaContainer'].get('Directory', [])
    mapping = []
    normalization_file = DATA / 'normalized-media-config.json'
    normalization = json.loads(normalization_file.read_text()) if normalization_file.exists() else {'libraries': []}
    for library in inventory['libraries']:
        if library['collectionType'] == 'tvshows':
            spec = {'type': 'show', 'agent': 'tv.plex.agents.series', 'scanner': 'Plex TV Series', 'language': 'en-US'}
        elif library['collectionType'] == 'movies':
            spec = {'type': 'movie', 'agent': 'tv.plex.agents.movie', 'scanner': 'Plex Movie', 'language': 'en-US'}
        else:
            spec = {'type': 'movie', 'agent': 'com.plexapp.agents.none', 'scanner': 'Plex Video Files Scanner', 'language': 'xn'}
        additional = [x['destination'] for x in normalization['libraries'] if x['name'] == library['name']]
        target_locations = library['locations'] + additional
        spec.update({'name': library['name'], 'location': target_locations})
        existing = next((x for x in sections if x['title'] == library['name']), None)
        if existing is None:
            created = request('/library/sections', spec, method='POST')['MediaContainer']['Directory'][0]
            key = created['key']
        else:
            key = existing['key']
            if existing['type'] != spec['type']:
                raise RuntimeError('Existing Plex library type differs for ' + library['name'])
            actual = sorted(x['path'] for x in existing.get('Location', []))
            changed = actual != sorted(target_locations)
            if changed:
                request('/library/sections/' + key, spec, method='PUT')
            if changed or refresh:
                request('/library/sections/' + key + '/refresh', raw=True)
        mapping.append({'name': library['name'], 'plexSectionID': key, 'locations': target_locations, 'sourceLocations': library['locations'], 'embyFiles': len(library['files']), 'type': spec['type']})
    request('/:/prefs', {'autoEmptyTrash': 0, 'FSEventLibraryUpdatesEnabled': 1, 'FSEventLibraryPartialScanEnabled': 1, 'ScheduledLibraryUpdatesEnabled': 1, 'ScheduledLibraryUpdateInterval': 3600}, method='PUT')
    save('libraries.json', request('/library/sections'))
    save('library-mapping.json', {'libraries': mapping, 'automaticRefreshSeconds': 3600})
    print(json.dumps({'mappedLibraries': len(mapping), 'embyTotalItems': inventory['totalItems'], 'embyTotalFiles': inventory['totalFiles'], 'libraries': mapping}, ensure_ascii=False))


def coverage(source_manifest=None):
    expected = emby_inventory()
    save('emby-full-inventory.json', expected)
    physical = json.loads(source_manifest.read_text()) if source_manifest and source_manifest.exists() else None
    if physical and physical.get('errors'):
        raise RuntimeError('Physical source inventory contains traversal errors')
    sections = request('/library/sections')['MediaContainer'].get('Directory', [])
    activities = request('/activities').get('MediaContainer', {}).get('Activity', [])
    active_scan = any(x.get('type') == 'library.update.section' for x in activities)
    result = []
    known_unplayable = {str(REPOSITORY.parent / 'TestMedia/TestVectors/Enchron/PlaybackBehavior/broken-clip.mp4')}
    def canonical(path):
        sample_root = str(DATA / 'samples') + '/'
        if path.startswith(sample_root):
            path = str(MEDIA / path[len(sample_root):])
        if path.startswith('/') and not path.startswith(str(MEDIA) + '/'):
            path = str(Path(path).resolve())
        return unicodedata.normalize('NFC', os.path.normpath(path))
    for library in expected['libraries']:
        section = next((x for x in sections if x['title'] == library['name']), None)
        normal = set()
        extras = set()
        inaccessible = set()
        references = {}
        media_items = 0
        def collect(items, destination):
            for item in items:
                for media in item.get('Media', []):
                    for part in media.get('Part', []):
                        path = part.get('file')
                        if path:
                            original_path = path
                            path = canonical(path)
                            reference = {'itemID': item.get('ratingKey'), 'mediaID': media.get('id'), 'partID': part.get('id'), 'file': original_path, 'legacySample': original_path.startswith(str(DATA / 'samples') + '/')}
                            identity = (reference['itemID'], reference['mediaID'], reference['partID'], reference['file'])
                            references.setdefault(path, {})[identity] = reference
                            if part.get('exists') is False or part.get('accessible') is False or part.get('exists') == 0 or part.get('accessible') == 0:
                                inaccessible.add(path)
                            else:
                                destination.add(path)
                collect(item.get('Extras', {}).get('Metadata', []), extras)
        if section:
            for item_type, destination in [(4 if section['type'] == 'show' else 1, normal), (12, extras)]:
                start = 0
                while True:
                    page = request('/library/sections/' + section['key'] + '/all', {'type': item_type, 'includeExtras': 1, 'X-Plex-Container-Start': start, 'X-Plex-Container-Size': 500})['MediaContainer']
                    values = page.get('Metadata', [])
                    if destination is normal:
                        media_items += len(values)
                    collect(values, destination)
                    start += len(values)
                    if start >= page.get('totalSize', page.get('size', 0)) or not values:
                        break
        actual = normal | extras
        emby_files = {canonical(path) for path in library['files']}
        physical_library = next((x for x in physical['libraries'] if x['name'] == library['name']), None) if physical else None
        physical_files = {canonical(x) for x in physical_library['paths']} if physical_library else None
        missing = sorted(emby_files - actual)
        physical_missing = sorted(physical_files - actual) if physical_files is not None else None
        valid_physical = physical_files - known_unplayable if physical_files is not None else None
        valid_missing = sorted(valid_physical - actual) if valid_physical is not None else None
        remaining = len(valid_missing if valid_missing is not None else missing)
        state = 'scanning' if section and section.get('refreshing', False) else 'queued' if active_scan and remaining else 'indexed' if remaining == 0 else 'incomplete'
        result.append({'name': library['name'], 'sectionID': section['key'] if section else None, 'expectedFiles': len(emby_files), 'physicalFiles': len(physical_files) if physical_files is not None else None, 'validPhysicalFiles': len(valid_physical) if valid_physical is not None else None, 'validPhysicalCoveredFiles': len(valid_physical & actual) if valid_physical is not None else None, 'knownUnplayableFiles': sorted(physical_files & known_unplayable) if physical_files is not None else [], 'visibleFiles': len(actual), 'visibleItems': media_items, 'normalFiles': len(normal), 'extrasFiles': len(extras), 'inaccessibleFiles': sorted(inaccessible), 'coveredFiles': len(emby_files & actual), 'physicalCoveredFiles': len(physical_files & actual) if physical_files is not None else None, 'missingFiles': missing, 'physicalMissingFiles': physical_missing, 'validPhysicalMissingFiles': valid_missing, 'extraFiles': sorted(actual - emby_files), 'scanning': section.get('refreshing', False) if section else False, 'state': state, 'duplicatePhysicalFiles': {path:list(refs.values()) for path,refs in references.items() if len(refs) > 1}, 'legacySampleReferences': {path:[ref for ref in refs.values() if ref['legacySample']] for path,refs in references.items() if any(ref['legacySample'] for ref in refs.values())}})
    report = {'capturedAt': time.time(), 'physicalInventoryCapturedAt': physical.get('observedAt') if physical else None, 'libraries': result, 'totalExpectedFiles': expected['totalFiles'], 'totalCoveredFiles': sum(x['coveredFiles'] for x in result), 'missingFiles': sum(len(x['missingFiles']) for x in result), 'totalPhysicalFiles': sum(x['physicalFiles'] for x in result) if physical else None, 'totalPhysicalCoveredFiles': sum(x['physicalCoveredFiles'] for x in result) if physical else None, 'totalValidPhysicalFiles': sum(x['validPhysicalFiles'] for x in result) if physical else None, 'totalValidPhysicalCoveredFiles': sum(x['validPhysicalCoveredFiles'] for x in result) if physical else None, 'physicalMissingFiles': sum(len(x['physicalMissingFiles']) for x in result) if physical else None, 'validPhysicalMissingFiles': sum(len(x['validPhysicalMissingFiles']) for x in result) if physical else None, 'scanning': active_scan or any(x['scanning'] for x in result), 'activities': [{k:x.get(k) for k in ['type','title','subtitle','progress']} for x in activities]}
    save('full-sync-coverage.json', report)
    with (SCRATCH / 'full-sync-progress.jsonl').open('a') as output:
        output.write(json.dumps({k:v for k,v in report.items() if k not in ['libraries','activities']}) + '\n')
    summary = {k:v for k,v in report.items() if k not in ['libraries','activities']}
    summary['libraries'] = [{k:v for k,v in x.items() if k not in ['missingFiles','physicalMissingFiles','extraFiles','inaccessibleFiles','validPhysicalMissingFiles','duplicatePhysicalFiles','legacySampleReferences']} for x in result]
    summary['activities'] = report['activities']
    print(json.dumps(summary, ensure_ascii=False))
    return report


def normalize():
    runtime = DATA / 'refresh_normalized_media.py'
    config_file = DATA / 'normalized-media-config.json'
    DATA.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(Path(__file__).with_name('plex_normalized_media.py'), runtime)
    sections = request('/library/sections')['MediaContainer'].get('Directory', [])
    section = next(x for x in sections if x['title'] == '电视剧')
    destination = DATA / 'normalized/电视剧'
    config = json.loads(config_file.read_text()) if config_file.exists() else {'libraries': []}
    if not any(x['sectionID'] == section['key'] for x in config['libraries']):
        config['libraries'].append({'name': '电视剧', 'sectionID': section['key'], 'destination': str(destination), 'rules': [{'source': str(MEDIA / '电视剧/凡人修仙传 (2020)'), 'series': '凡人修仙传 (2020)', 'season': 1}]})
    config_file.write_text(json.dumps(config, ensure_ascii=False, indent=2) + '\n')
    subprocess.run(['/usr/bin/python3', str(runtime), '--config', str(config_file), '--no-refresh'], check=True)
    locations = [x['path'] for x in section.get('Location', [])]
    if str(destination) not in locations:
        request('/library/sections/' + section['key'], {'name': section['title'], 'type': section['type'], 'location': locations + [str(destination)], 'agent': section['agent'], 'scanner': section['scanner'], 'language': section['language']}, method='PUT')
        request('/library/sections/' + section['key'] + '/refresh', raw=True)
    label = 'com.enchron.plex-normalized-media'
    launch = Path.home() / 'Library/LaunchAgents' / (label + '.plist')
    launch.write_bytes(plistlib.dumps({'Label': label, 'ProgramArguments': ['/usr/bin/python3', str(runtime), '--config', str(config_file)], 'RunAtLoad': True, 'StartInterval': 3600, 'StandardOutPath': str(DATA / 'normalized-media.stdout.log'), 'StandardErrorPath': str(DATA / 'normalized-media.stderr.log')}))
    domain = 'gui/' + str(os.getuid())
    if subprocess.run(['launchctl', 'print', domain + '/' + label], capture_output=True).returncode != 0:
        subprocess.run(['launchctl', 'bootstrap', domain, str(launch)], check=True)
    save('normalization.json', {'runtime': str(runtime), 'config': str(config_file), 'label': label, 'refreshSeconds': 3600, 'location': str(destination)})


def collection():
    sections = request('/library/sections')['MediaContainer'].get('Directory', [])
    section = next(x for x in sections if x['title'] == '电影')
    items = request('/library/sections/' + section['key'] + '/all', {'type': 1})['MediaContainer'].get('Metadata', [])
    members = [x for x in items if x['title'] in ['Blade Runner', 'Blade Runner 2049']]
    if len(members) != 2:
        raise RuntimeError('Both Blade Runner sample movies must be ready')
    title = 'Enchron Verification Collection'
    existing = request('/library/sections/' + section['key'] + '/all', {'type': 18})['MediaContainer'].get('Metadata', [])
    entry = next((x for x in existing if x['title'] == title), None)
    if entry is None:
        identity = request('/identity')['MediaContainer']['machineIdentifier']
        uri = 'server://' + identity + '/com.plexapp.plugins.library/library/metadata/' + ','.join(x['ratingKey'] for x in members)
        result = request('/library/collections', {'type': 1, 'title': title, 'smart': 0, 'sectionId': section['key'], 'uri': uri}, method='POST')
        entry = result['MediaContainer']['Metadata'][0]
    actual = request('/library/metadata/' + entry['ratingKey'] + '/children')['MediaContainer'].get('Metadata', [])
    if {x['ratingKey'] for x in actual} != {x['ratingKey'] for x in members}:
        raise RuntimeError('Existing test collection has unexpected members')
    save('collection-detail.json', request('/library/metadata/' + entry['ratingKey']))
    print(json.dumps({'collectionID': entry['ratingKey'], 'title': title, 'members': [x['title'] for x in actual]}, ensure_ascii=False))


def probe():
    identity = request('/identity')['MediaContainer']
    sections = request('/library/sections')['MediaContainer'].get('Directory', [])
    report = {'identity': identity, 'libraries': [], 'mediaRead': None, 'artworkRead': None, 'timeline': None}
    fixture = None
    movie = None
    episode = None
    stream_fixture = None
    for section in sections:
        items = request('/library/sections/' + section['key'] + '/all', {'type': 4 if section['type'] == 'show' else 1})['MediaContainer'].get('Metadata', [])
        report['libraries'].append({'key': section['key'], 'title': section['title'], 'count': len(items), 'refreshing': section.get('refreshing', False)})
        save('items-' + section['key'] + '.json', {'MediaContainer': {'Metadata': items}})
        if section['title'] == 'Enchron Verification':
            fixture = next((i for i in items if i['title'] == 'reachability-resume-16m'), None)
            stream_fixture = next((i for i in items if i['title'] == 'sdr-bframe-aggregate-30s'), None)
        if section['title'] == '电视剧' and items:
            episode = items[0]
        if section['title'] == '电影' and items:
            movie = items[0]
    if stream_fixture:
        save('stream-detail.json', request(stream_fixture['key']))
    if episode:
        detail = request(episode['key'])
        save('episode-detail.json', detail)
        item = detail['MediaContainer']['Metadata'][0]
        save('series-detail.json', request('/library/metadata/' + item['grandparentRatingKey']))
        part = item['Media'][0]['Part'][0]
        status, headers, body = request(part['key'], raw=True, extra_headers={'Range': 'bytes=0-4095'})
        with Path(part['file']).open('rb') as source:
            expected = source.read(4096)
        report['episodeMediaRead'] = {'status': status, 'bytes': len(body), 'contentRange': headers.get('Content-Range'), 'matchesSource': body == expected}
        if item.get('thumb'):
            status, headers, body = request(item['thumb'], raw=True)
            report['episodeArtworkRead'] = {'status': status, 'bytes': len(body), 'contentType': headers.get('Content-Type'), 'title': item['title']}
    if fixture:
        detail = request(fixture['key'])
        save('fixture-detail.json', detail)
        item = detail['MediaContainer']['Metadata'][0]
        part = item['Media'][0]['Part'][0]
        status, headers, body = request(part['key'], raw=True, extra_headers={'Range': 'bytes=0-4095'})
        source = Path(part['file'])
        with source.open('rb') as file:
            expected = file.read(4096)
        report['mediaRead'] = {'status': status, 'bytes': len(body), 'contentRange': headers.get('Content-Range'), 'matchesSource': body == expected, 'sha256': hashlib.sha256(body).hexdigest()}
        before = item.get('viewOffset', 0)
        position = 240000 if before == 120000 else 120000
        for state in ['playing', 'paused', 'stopped']:
            status, _, _ = request('/:/timeline', {'ratingKey': item['ratingKey'], 'key': item['key'], 'state': state, 'time': position, 'duration': item['duration'], 'playQueueItemID': 0}, raw=True)
        after = request(item['key'])['MediaContainer']['Metadata'][0].get('viewOffset', 0)
        report['timeline'] = {'status': status, 'before': before, 'sentMilliseconds': position, 'persistedMilliseconds': after, 'ratingKey': item['ratingKey']}
        if before == 0 and not item.get('viewCount'):
            request('/:/unscrobble', {'key': item['ratingKey'], 'identifier': 'com.plexapp.plugins.library'}, raw=True)
        else:
            request('/:/timeline', {'ratingKey': item['ratingKey'], 'key': item['key'], 'state': 'stopped', 'time': before, 'duration': item['duration']}, raw=True)
        report['timeline']['restoredMilliseconds'] = request(item['key'])['MediaContainer']['Metadata'][0].get('viewOffset', 0)
    if movie:
        detail = request(movie['key'])
        save('movie-detail.json', detail)
        item = detail['MediaContainer']['Metadata'][0]
        part = item['Media'][0]['Part'][0]
        status, headers, body = request(part['key'], raw=True, extra_headers={'Range': 'bytes=0-4095'})
        with Path(part['file']).open('rb') as source:
            expected = source.read(4096)
        report['cloudMediaRead'] = {'status': status, 'bytes': len(body), 'contentRange': headers.get('Content-Range'), 'matchesSource': body == expected}
        if item.get('thumb'):
            status, headers, body = request(item['thumb'], raw=True)
            report['artworkRead'] = {'status': status, 'bytes': len(body), 'contentType': headers.get('Content-Type'), 'title': item['title']}
    save('health.json', report)
    print(json.dumps(report, ensure_ascii=False))
    if not fixture or not report['mediaRead']['matchesSource'] or report['timeline']['persistedMilliseconds'] != report['timeline']['sentMilliseconds'] or not report['artworkRead'] or not report.get('episodeArtworkRead') or not report.get('episodeMediaRead', {}).get('matchesSource'):
        raise RuntimeError('Plex samples are not fully ready; inspect health.json and retry after scan')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['install', 'libraries', 'normalize', 'collection', 'coverage', 'probe'])
    parser.add_argument('--refresh', action='store_true')
    parser.add_argument('--source-manifest', type=Path, default=SCRATCH / 'source-manifest.local.json')
    arguments = parser.parse_args()
    if arguments.action == 'libraries':
        libraries(arguments.refresh)
        return
    if arguments.action == 'coverage':
        coverage(arguments.source_manifest)
        return
    {'install': install, 'libraries': libraries, 'collection': collection, 'coverage': coverage, 'normalize': normalize, 'probe': probe}[arguments.action]()


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(type(error).__name__ + ': ' + str(error), file=sys.stderr)
        sys.exit(1)
