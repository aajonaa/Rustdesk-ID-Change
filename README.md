# Rustdesk-ID-Change
The script use to change the rustdesk ID. As a open source remote control software, the "once good" a software can not manually change the ID even though you have host your own ID server or relay server. That sucks, I gathered the issue in the rustdesk and paied my effort to try to fix this problem. Both Windows and Linux works (version 1.3.8)~

# The script to modify the rustdesk id of windows and the linux (rustdesk v1.3.8)
- Both can run remotely, it will automatically restart the rustdesk service
- The best way is to use ssh to see how it works and the process
- Since the rustdesk will down when you input the new ID name  
- Windows shell may not be able to enter the powershell mode)
- Windows using the irm url | iex to execute
- Linux using the bash script to run it

## Windows script
- Write the powershell script file
- Using nginx to host them
- Execute irm url | iex
  - irm -> Invoke-Expression
  - iex -> Invoke-RestMethod 

## The logic behind the linux id change
- Stop rustdesk service: systemctl stop rustdesk.service
- Back up original toml file: cp RustDesk.toml RustDesk.toml.bak
- Write the line (id = "desiredID") to file RustDesk.toml
- Start rustdesk service to see the encID value
  - systemctl start rustdesk.service
  - cat RustDesk.toml (you will see the encryped id value)
- Substitute the original encID with the desired one
- Make the file unmutable: chattr +i Rustdesk.toml
- Start the rustdesk to see the final result

