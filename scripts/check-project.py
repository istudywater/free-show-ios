"""Check source membership and shared scheme references without requiring Xcode."""
import plistlib
import subprocess
import xml.etree.ElementTree as ET
from pathlib import Path

root = Path(__file__).resolve().parent.parent
project_path = root / 'FreeShowController.xcodeproj/project.pbxproj'
xml = subprocess.check_output(['plutil', '-convert', 'xml1', '-o', '-', str(project_path)])
project = plistlib.loads(xml)
objects = project['objects']
targets = [item for item in objects.values() if item['isa'] == 'PBXNativeTarget']
assert len(targets) == 1, 'Expected one application target'
target = targets[0]
source_phases = [objects[key] for key in target['buildPhases'] if objects[key]['isa'] == 'PBXSourcesBuildPhase']
assert len(source_phases) == 1
compiled = []
for build_id in source_phases[0]['files']:
    reference = objects[objects[build_id]['fileRef']]
    assert reference['sourceTree'] == 'SOURCE_ROOT'
    path = reference['path']
    assert (root / path).is_file(), f'Missing source: {path}'
    compiled.append(path)
expected = {path.relative_to(root).as_posix() for path in (root / 'FreeShowController').rglob('*.swift')}
assert set(compiled) == expected, 'Project source membership differs from files on disk'
assert len(compiled) == len(set(compiled)), 'Duplicate source membership'
scheme = ET.parse(root / 'FreeShowController.xcodeproj/xcshareddata/xcschemes/FreeShowController.xcscheme')
for ref in scheme.iter('BuildableReference'):
    assert objects[ref.attrib['BlueprintIdentifier']] == target
    assert ref.attrib['ReferencedContainer'] == 'container:FreeShowController.xcodeproj'
for config_id in objects[target['buildConfigurationList']]['buildConfigurations']:
    settings = objects[config_id]['buildSettings']
    assert str(settings['TARGETED_DEVICE_FAMILY']) == '2'
    assert settings['SUPPORTED_PLATFORMS'] == 'iphoneos iphonesimulator'
print(f'Project references and scheme passed: {len(compiled)} Swift sources, iPad-only target.')
