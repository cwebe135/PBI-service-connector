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

# location of current .mez file
debug_mez = 'bin/AnyCPU/Debug/PBIServiceMetadata.mez'

# get list of files in current .mez
with zipfile.ZipFile(debug_mez, 'r') as zip_old:
    file_list = zip_old.namelist()

# create a new .mez with the same files in it
z_new = zipfile.ZipFile(debug_mez, 'w')
for file in file_list:
    z_new.write(file)
z_new.close()
print("New .mez file created")

if platform.system() == 'Windows' and len(sys.argv) > 1 and sys.argv[1] == "distribute":
    # Power BI Desktop only available for Windows systems
    # Copies .mez into Custom Connectors directory
    from shutil import copyfile
    from ctypes import wintypes, windll, create_unicode_buffer

    # get local output path for custom connectors
    buffer = create_unicode_buffer(wintypes.MAX_PATH)
    windll.shell32.SHGetFolderPathW(None, 5, None, 0, buffer) # `5` is Documents folder
    customConnectorsDirectory = buffer.value

    os.makedirs(customConnectorsDirectory + '/Microsoft Power BI Desktop/Custom Connectors', exist_ok=True)

    copyfile(debug_mez, customConnectorsDirectory + '/Microsoft Power BI Desktop/Custom Connectors/PBIServiceMetadata.mez')
    print(".mez file copied to Custom Connectors directory")