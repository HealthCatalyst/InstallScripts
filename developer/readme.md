This is not production ready code!

To bring up the main menu, just open PowerShell and paste:
Invoke-WebRequest -useb https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/3/developer/runengine.ps1 | Invoke-Expression;

This uses a library of functions that automate some parts of DOS.  You can just pull in the library only by pasting:
Invoke-WebRequest -useb https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/3/developer/doslibrary.ps1 | Invoke-Expression;


