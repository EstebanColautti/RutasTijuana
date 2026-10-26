import http.client
import json
import os
import socket

class Connection(http.client.HTTPConnection):
    def connect(self):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.connect('/run/user/' + str(os.getuid()) + '/podman/podman.sock')

def request(method, path, body=None):
    connection = Connection('localhost')
    connection.request(method, '/v1.41' + path, None if body is None else json.dumps(body), {'Content-Type':'application/json'})
    response = connection.getresponse()
    data = response.read()
    if response.status >= 300 and response.status != 304:
        raise RuntimeError('Contenedor: ' + str(response.status) + ' ' + str(json.loads(data).get('message','')))
    return json.loads(data) if data else None

for name in ('supabase_db_rutastijuana', 'supabase_kong_rutastijuana', 'supabase_inbucket_rutastijuana'):
    container = request('GET', '/containers/' + name + '/json')
    bindings = container['HostConfig'].get('PortBindings') or {}
    if all(item.get('HostIp') == '127.0.0.1' for values in bindings.values() for item in (values or [])):
        continue
    image = request('POST', '/commit?container=' + name + '&pause=false')
    spec = dict(container['Config'])
    spec['Image'] = image['Id']
    spec['HostConfig'] = container['HostConfig']
    spec['HostConfig'].pop('MemorySwappiness', None)
    for values in bindings.values():
        for item in values or []:
            item['HostIp'] = '127.0.0.1'
    spec['HostConfig']['PortBindings'] = bindings
    spec['NetworkingConfig'] = {'EndpointsConfig': {network: {'Aliases':[name]} for network in container['NetworkSettings']['Networks']}}
    backup = name + '_binding_backup'
    request('POST', '/containers/' + name + '/stop?t=30')
    request('POST', '/containers/' + name + '/rename?name=' + backup)
    try:
        request('POST', '/containers/create?name=' + name, spec)
        request('POST', '/containers/' + name + '/start')
    except Exception:
        try:
            request('DELETE', '/containers/' + name + '?force=true&v=false')
        finally:
            request('POST', '/containers/' + backup + '/rename?name=' + name)
            request('POST', '/containers/' + name + '/start')
        raise
    request('DELETE', '/containers/' + backup + '?v=false')
    print(name + ': 127.0.0.1')
