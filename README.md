# Rustdesk-ID-Change

- The script use to change the rustdesk ID. As a open source remote control software, the "once good" a software can not manually change the ID even though you have host your own ID server or relay server.
- That sucks, I gathered the issue in the rustdesk and paied my effort to try to fix this problem. Both Windows, Linux, and MacOS works
- If you want to know more detail about how to id change works, you can look into the source code of those file
- Actually, it is pretty simple to reverse engineer the rustdesk id change, only need to change the toml file with string 'id = "desired_id"', and then the enc_id corresponding to this id will be generated.
- Even more, the enc_id, the password, the key_paris, are all separated, it means that if you have the enc_id of the desired id, then you can change the id of rustdesk while maintaining all other settings unchanged.

# The script to modify the rustdesk id of windows, linux, and MacOS

- Both can run remotely, it will automatically restart the rustdesk service
- The best way is to use ssh to see how it works and the process
- Since the rustdesk will down when you input the new ID name
- Windows shell may not be able to enter the powershell mode)
- Windows using the irm url | iex to execute (url -> powershell file)
- Linux using the bash script to run it
- MacOs using the bash script to run it

## The logic behind the linux id change(v1.3.8 verified)

### General process: Back toml file -> Add a new line to toml file (id = "desired_id") -> start the rustdesk

- Write the powershell script file
- Using nginx to host them
- Execute irm url | iex
  - irm -> Invoke-Expression
  - iex -> Invoke-RestMethod

## The logic behind the linux id change (v1.3.8 verified)

### General process: Back toml file -> generate enc_id -> inject this enc_id to the original toml file

- Stop rustdesk service: systemctl stop rustdesk.service
- Back up original toml file: cp RustDesk.toml RustDesk.toml.bak
- Write the line (id = "desiredID") to file RustDesk.toml
- Start rustdesk service to see the encID value
  - systemctl start rustdesk.service
  - cat RustDesk.toml (you will see the encryped id value)
- Substitute the original encID with the desired one
- Make the file unmutable: chattr +i Rustdesk.toml
- Start the rustdesk to see the final result

## The logic behind the MacOS id change (v1.3.9 verified)

### General process: back toml file -> generate enc_id (new toml file) -> restore password

- plist file location: /Users/jona/library/Preferences/com.carriez.rustdesk.plist
- RustDesk.toml file location: /Users/jona/library/Preferences/com.carriez.RustDesk/RustDesk.toml
- MacOS's script is diff with the one in the linux
  - Because when we execute the commad equivalent to the 'systemctl start rustdesk.service'
  - The GUI of MacOS rustdesk opened automatically which will autogenerate the toml file based on the new desired id
  - So all the settings are diff with the previous one and the password is initially empty
  - Thus we extract the password value from the original toml file and inject it to the new toml file
  - And then make it immutable
