import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import time
import urllib.parse
import urllib.request

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
    (SCRATCH / name).write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')


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
    request('/:/prefs', {'FriendlyName': 'Enchron Plex', 'GenerateBIFBehavior': 'never', 'GenerateChapterThumbBehavior': 'never', 'FSEventLibraryUpdatesEnabled': 0, 'ScheduledLibraryUpdatesEnabled': 0}, method='PUT')
    print(json.dumps({'address': payload['address'], 'version': identity['version'], 'credentials': str(CREDENTIALS)}))


def link(source, target):
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.is_symlink():
        if target.resolve() != source.resolve():
            raise RuntimeError('Unexpected existing sample link: ' + str(target))
    elif target.exists():
        raise RuntimeError('Sample target is not a symlink: ' + str(target))
    else:
        target.symlink_to(source)
        return True
    return False


def libraries():
    sample_files = []
    changed = set()
    for folder in ['Blade Runner (1982)', 'Blade Runner 2049 (2017)']:
        root = MEDIA / '电影' / folder
        for movie in root.iterdir():
            if movie.suffix.lower() in ['.mkv', '.mp4']:
                target = DATA / 'samples/电影' / folder / movie.name
                if link(movie, target):
                    changed.add('电影')
                sample_files.append({'source': str(movie), 'link': str(target)})
    episode_root = MEDIA / '电视剧/黑镜 (2011)/Season 01'
    for episode in episode_root.iterdir():
        if episode.suffix.lower() in ['.mkv', '.mp4']:
            target = DATA / 'samples/电视剧/黑镜 (2011)/Season 01' / episode.name
            if link(episode, target):
                changed.add('电视剧')
            sample_files.append({'source': str(episode), 'link': str(target)})
    specs = [
        {'name': 'Enchron Verification', 'type': 'movie', 'agent': 'com.plexapp.agents.none', 'scanner': 'Plex Video Files Scanner', 'language': 'xn', 'location': str(REPOSITORY.parent / 'TestMedia/TestVectors/Enchron/PlaybackBehavior')},
        {'name': 'Enchron Regression Emby', 'type': 'show', 'agent': 'tv.plex.agents.series', 'scanner': 'Plex TV Series', 'language': 'en-US', 'location': '/Volumes/Cortisol/DevSpace/orca/workspace/Enchron/harness-emby-signin/.build/regression-emby-source/library'},
        {'name': '电影', 'type': 'movie', 'agent': 'tv.plex.agents.movie', 'scanner': 'Plex Movie', 'language': 'en-US', 'location': str(DATA / 'samples/电影')},
        {'name': '电视剧', 'type': 'show', 'agent': 'tv.plex.agents.series', 'scanner': 'Plex TV Series', 'language': 'en-US', 'location': str(DATA / 'samples/电视剧')}
    ]
    sections = request('/library/sections')['MediaContainer'].get('Directory', [])
    for spec in specs:
        existing = next((s for s in sections if s['title'] == spec['name']), None)
        if not existing:
            request('/library/sections', spec, method='POST')
        elif spec['name'] in changed:
            request('/library/sections/' + existing['key'] + '/refresh', raw=True)
    result = request('/library/sections')
    save('libraries.json', result)
    save('library-mapping.json', {'libraries': specs, 'samples': sample_files})
    print(json.dumps({'libraries': [s['title'] for s in result['MediaContainer'].get('Directory', [])]}, ensure_ascii=False))


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
    parser.add_argument('action', choices=['install', 'libraries', 'probe'])
    arguments = parser.parse_args()
    {'install': install, 'libraries': libraries, 'probe': probe}[arguments.action]()


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(type(error).__name__ + ': ' + str(error), file=sys.stderr)
        sys.exit(1)
