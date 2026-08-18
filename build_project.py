# -------------------------------------------------------------------
# Builds .mez file for debugging
#
# If called with `distribute` argument and running on Windows, copies
# the new .mez file into Power BI's Custom Connectors directory.
# -------------------------------------------------------------------

import platform
import zipfile
import sys
import os
import xml.etree.ElementTree as ET

# get configurations for .mez
projTree = ET.parse('PBI Service Metadata.proj')
projRoot = projTree.getroot()
# get properties
propertyElement = projRoot.find('PropertyGroup')
properties = {child.tag: child.text for child in propertyElement}
# get files
itemsElement = projRoot.find('ItemGroup')
items = [child.attrib['Include'] for child in itemsElement.findall('MezContent')]

debugMez = properties['MezOutputPath'].format(**properties)
os.makedirs(properties['OutputPath'], exist_ok=True)

# create a new .mez with the same files in it
z_new = zipfile.ZipFile(debugMez, 'w')
for file in items:
    z_new.write(file)
z_new.close()
print("New .mez file created")

# Copy .mez into Custom Connectors directory
if platform.system() == 'Windows' and len(sys.argv) > 1 and sys.argv[1] == "distribute":
    # Power BI Desktop only available for Windows systems
    
    from shutil import copyfile
    from ctypes import wintypes, windll, create_unicode_buffer

    # get local output path for custom connectors
    buffer = create_unicode_buffer(wintypes.MAX_PATH)
    windll.shell32.SHGetFolderPathW(None, 5, None, 0, buffer) # `5` is Documents folder
    customConnectorsDirectory = buffer.value

    os.makedirs(customConnectorsDirectory + '/Microsoft Power BI Desktop/Custom Connectors', exist_ok=True)

    copyfile(debugMez, customConnectorsDirectory + '/Microsoft Power BI Desktop/Custom Connectors/PBIServiceMetadata.mez')
    print(".mez file copied to Custom Connectors directory")