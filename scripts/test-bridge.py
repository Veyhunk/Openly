#!/usr/bin/env python3
"""Exercise native messaging framing, one-shot claims and input boundaries."""
import json, os, struct, subprocess, tempfile, time, uuid
from pathlib import Path
root = Path(__file__).resolve().parent.parent
binary = os.environ.get('OPENLY_BRIDGE_BINARY')
if not binary:
    bin_dir = Path(subprocess.check_output(['swift', 'build', '--show-bin-path'], cwd=root, text=True).strip())
    binary = str(bin_dir / 'OpenlyBridge')
with tempfile.TemporaryDirectory(prefix='openly-bridge-test-') as directory:
    folder = Path(directory) / 'bridge'; folder.mkdir()
    env = {**os.environ, 'OPENLY_STATE_DIR': directory}
    def send(message):
        data = json.dumps(message).encode()
        result = subprocess.run([binary], input=struct.pack('<I', len(data)) + data, capture_output=True, check=True, env=env)
        length = struct.unpack('<I', result.stdout[:4])[0]
        return json.loads(result.stdout[4:4 + length])
    assert send({'token': '../../arbitrary', 'action': 'claim'}) == {'error': 'Invalid request'}
    token = str(uuid.uuid4()); request = {'expires': time.time() + 30, 'action': 'list'}
    (folder / (token + '.json')).write_text(json.dumps(request))
    assert send({'token': token, 'action': 'claim'}) == request
    assert 'error' in send({'token': token, 'action': 'claim'})
    assert send({'token': token, 'action': 'complete', 'result': {'windows': []}}) == {'ok': True}
    assert json.loads((folder / (token + '.result.json')).read_text()) == {'windows': []}
    assert 'error' in send({'token': token, 'action': 'complete', 'result': {}})
    expired = str(uuid.uuid4()); (folder / (expired + '.json')).write_text(json.dumps({'expires': 0}))
    assert 'error' in send({'token': expired, 'action': 'claim'})
print('PASS: native messaging path validation, claim/replay, completion, expiry')
