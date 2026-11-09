import copy
import json
import tempfile
import unittest
from pathlib import Path
from scripts.build_catalog import build
from scripts.install_catalog import fixture, validate

class CatalogPackageTests(unittest.TestCase):
    def raw(self):
        return dict(groups=[dict(id='g',name='Ejemplo')],features=[dict(id='r',name='Recorrido',groupID='g',kind='route',color='#2476E8',geometry=dict(type='LineString',coordinates=[[-117,32],[-117,32.01]]),information=dict(description='PRIVATE_DESCRIPTION',fields=[dict(category='fare',label='PRIVATE_LABEL',value='$15',evidence='PRIVATE_EVIDENCE'),dict(category='source',label='Origen',value='PRIVATE_SOURCE'),dict(category='schedule',label='Horario',value='https://private.example')]),privateNotes='PRIVATE_NOTES',source='PRIVATE_SOURCE',routeDetails=dict(code='E1',circular=False,private='PRIVATE_DETAIL'))])
    def test_projection(self):
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'catalog'
            first=build(self.raw(),path)
            validate(path)
            payload=(path/'catalog.json').read_text(encoding='utf-8')
            self.assertNotIn('PRIVATE',payload)
            self.assertNotIn('https:',payload)
            self.assertEqual(json.loads(payload)['features'][0]['information']['fields'],[dict(category='fare',label='Tarifa',value='$15')])
            self.assertEqual(first,build(self.raw(),path))
    def test_failed_build_preserves_previous(self):
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'catalog'; build(self.raw(),path)
            previous=(path/'catalog.json').read_bytes()
            invalid=self.raw(); invalid['features'][0]['color']='bad'
            with self.assertRaises(ValueError): build(invalid,path)
            self.assertEqual(previous,(path/'catalog.json').read_bytes())
    def test_fixture_and_tamper(self):
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder); fixture(path); manifest=validate(path)
            image=path/manifest['assets'][0]['downloadURL']
            image.write_bytes(b'corrupt')
            with self.assertRaises(ValueError): validate(path)
    def test_extra_files_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'catalog'; build(self.raw(),path)
            (path/'notes.txt').write_text('PRIVATE')
            with self.assertRaises(ValueError): validate(path)
            with self.assertRaises(ValueError): build(self.raw(),path)

if __name__=='__main__': unittest.main()
