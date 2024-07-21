# Mass deployment Network/USB bootable repair for Crowdstrike SYS file issue

This script was generated as a method to mass deploy a fix of the recommended approach to delete the faulty sys file from Crowdstrike causing the issue. This is based around the WinPE and WinRE approach approach to deploy images back in my old days of imaging and packaging (2009). It uses PowerShell and trys to get AD to get Bitlocker (which should be enabled) and LAPS (Passwords for Local admin stored in AD). It can work on Active Directory or Entera (Active Directory). The PowerShell script can be modified as necessary. It by default asks if you have AD, AAD(Entra) or local. You can change it from a Light Touch to Zero Touch approach with modifications. A directory can be specified with keys to test. This can be added later in the USB as well.

Creating a Windows Recovery Environment (WinRE) bootable ISO that can run a PowerShell script involves several steps. Here's a concise guide to help you through the process that was written by several copilot queries and applied to this particular instance. Change and update as required. Test before deploying out:

1. **Prepare a local copy of the Windows PE files:**
   - Download and install the Windows Assessment and Deployment Kit (ADK) and the WinPE add-on `https://docs.microsoft.com/en-us/windows-hardware/get-started/adk-install`.
   - Start the Deployment and Imaging Tools Environment as an administrator.
   - Make the mount directory in the root of C drive
   - Create a working copy of the Windows PE files using the `copype amd64 C:\Mount\WinRE` command.
   - Alternately mount the WinPE image using the `powershell Mount-WindowsImage -ImagePath "C:\Path\To\winre.wim" -Index 1 -Path "C:\Mount\WinRE"` command.
   - If you have several bitlocker keys and want to try to unlock by the script trying one by one create a directory called bitlocker and add the keys there.

2. **Add PowerShell support to WinPE:**
   - Add networking and PowerShell support using the following:
     ```
     dism /mount-wim /wimfile:C:\WinPE_amd64\media\sources\boot.wim /index:1 /mountdir:C:\WinPE_amd64\mount
     dism /image:C:\WinPE_amd64\mount /add-package /packagepath:"C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\WinPE_OCs\WinPE-WMI.cab"
     dism /image:C:\WinPE_amd64\mount /add-package /packagepath:"C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\WinPE_OCs\WinPE-NetFX.cab"
     dism /image:C:\WinPE_amd64\mount /add-package /packagepath:"C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\WinPE_OCs\WinPE-Scripting.cab"
     dism /image:C:\WinPE_amd64\mount /add-package /packagepath:"C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\WinPE_OCs\WinPE-PowerShell.cab"
     dism /image:C:\WinPE_amd64\mount /add-package /packagepath:"C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\WinPE_OCs\WinPE-DismCmdlets.cab"
     dism /image:C:\WinPE_amd64\mount /add-package /packagepath:"C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\WinPE_OCs\WinPE-WiFi.cab"
     ```

3. **Add PowerShell AzureAD support to WinPE:**
   - Import-Module AzureAD to your computer to add to the image `Install-Module -Name AzureAD`
   - Add the AzureAD modules: `powershell Copy-Item -Path "C:\Program Files\WindowsPowerShell\Modules\AzureAD" -Destination "C:\Mount\WinRE\Program Files\WindowsPowerShell\Modules" -Recurse`

4. **Create your PowerShell script:**
   - Write your PowerShell script in Notepad and save it with a `.ps1` extension. As an example using the fix-crowdstrike.ps1 created before.

5. **Integrate your PowerShell script into WinPE:**
   - Place your PowerShell script in the `Scripts` folder within the mounted WinPE image.
   - Modify the `startnet.cmd` file to call your PowerShell script upon boot. As an example using the fix-crowdstrike.ps1 the command would be:
     ```
     wpeinit
     PowerShell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process PowerShell.exe -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File ""X:\Scripts\fix-crowdstrike.ps1"' -Verb RunAs"
     ```

6A. **Add network support to image (Wireless)**
   - Create an XML file with the Wireless credentials such as `C:\Temp\WirelessProfile.xml`. Modify SSID value of YourNetworkName and Wireless password YourPassword. The below is for WPA password. Use any as available for your connection (Enterprise wireless and certificates etc)
     ```xml
     <?xml version="1.0"?>
     <WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
         <name>YourNetworkName</name>
         <SSIDConfig>
             <SSID>
                 <name>YourNetworkName</name>
             </SSID>
         </SSIDConfig>
         <connectionType>ESS</connectionType>
         <connectionMode>auto</connectionMode>
         <MSM>
             <security>
                 <authEncryption>
                     <authentication>WPA2PSK</authentication>
                     <encryption>AES</encryption>
                     <useOneX>false</useOneX>
                 </authEncryption>
                 <sharedKey>
                     <keyType>passPhrase</keyType>
                     <protected>false</protected>
                     <keyMaterial>YourPassword</keyMaterial>
                 </sharedKey>
             </security>
         </MSM>
     </WLANProfile>
     ```
   - Move the XML file into the WinPE `Copy-Item -Path "C:\Temp\WirelessProfile.xml" -Destination c:\mount\Winre\Windows\System32"`
   - Modify the `startnet.cmd` file to call your PowerShell script upon boot after starting the WiFi. As an example using the fix-crowdstrike.ps1 the command would be included as well.
     ```
     wpeinit
     netsh wlan add profile filename="X:\Windows\System32\WirelessProfile.xml"
     netsh wlan connect name="YourNetworkName"
     PowerShell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process PowerShell.exe -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File ""X:\Scripts\fix-crowdstrike.ps1"' -Verb RunAs"
     ```

6B. **Add network support to image (Wired ethernet)**
   - Download the necessary amd64 or arm64 drivers as per image requirements and import into the image using dism `dism /image:C:\mount\winre /add-driver /driver:"C:\Path\To\Ethernet\Drivers" /recurse`
   - Modify the `startnet.cmd` file to call your PowerShell script upon boot after starting the ethernet connection. As an example using the fix-crowdstrike.ps1 the command would be included as well.
     ```
     wpeinit
     net start dhcp
     net start nlasvc
     netsh interface ip set dns name="Ethernet" source=dhcp
     netsh interface ip set address name="Ethernet" source=dhcp
     PowerShell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process PowerShell.exe -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File ""X:\Scripts\fix-crowdstrike.ps1"' -Verb RunAs"
     ```

7. **Unmount the image** using the following: `dism /unmount-wim /mountdir:C:\mount\winre /commit`

8A. **Create the ISO image:**
   - Use the `oscdimg` tool to create an ISO from the modified WinPE image.
   - Burn the ISO to a USB or DVD, or mount it in a virtual machine to test the boot process and script execution.

8B. **Create a bootable USB:**
   - Use the following command to create a bootable USB on an example F drive:
     ```
     MakeWinPEMedia /UFD C:\WinPE_amd64 F:
     ```

The below instructions are from Copilot and less specific. Please see below sources as required and implement as you see fit.

For detailed instructions and commands, you can refer to the resources provided by Microsoft⁵ and other technical articles⁴. Remember to replace the paths and commands with those specific to your environment and script.

Please note that you'll need administrative privileges to perform these actions and ensure that your script complies with your system's security policies. If you encounter any issues, the error messages are usually quite informative, and you can use them to troubleshoot further.

To create a deployable image for SCCM or Intune, you can follow these additional steps:

**For SCCM:**
1. **Create an Image Package:**
   - Use the SCCM Console to create an image package from the `install.wim` file.
   - Distribute the package to the distribution point.
2. **Create a Task Sequence:**
   - Set up a task sequence that installs the image package, partitions and formats the hard drive, joins the domain, and configures settings like cache size and BitLocker.
3. **Deploy the Task Sequence:**
   - Deploy the task sequence to target devices or collections.
4. **Monitor the Deployment:**
   - Monitor the deployment process through the SCCM console to ensure successful completion¹.

**For Intune:**
1. **Prepare the SCCM Client:**
   - Use the `IntuneWinAppUtil.exe` tool to create an `.intunewin` file from the SCCM client folder.
2. **Upload to Intune:**
   - Upload the `.intunewin` file to Intune as a Win32 app and provide the necessary app information, program properties, requirements, detection rules, dependencies, and supersedence.
3. **Assign the App:**
   - Assign the app to user groups and make it available for installation through the company portal².

For both SCCM and Intune, ensure that your PowerShell script is included in the image and configured to run at the desired point in the deployment process. You may need to adjust the task sequence or app configuration to include the script execution.

Remember to test the deployment on a small set of devices before rolling it out organization-wide to ensure that everything works as expected. If you need more detailed instructions, you can refer to the video tutorials and guides provided in the search results for step-by-step guidance³⁴.

To retrieve the BitLocker recovery key for an existing machine using SCCM or Intune, you can follow these steps:

**For SCCM:**
1. **Access the Admin Center:**
   - In a browser, go to the Microsoft Intune admin center.
2. **Navigate to Devices:**
   - Select 'Devices' and then 'All Devices'.
3. **Select the Device:**
   - Choose a device that's synced from Configuration Manager via tenant attach.
4. **Find the Recovery Keys:**
   - Click on 'Recovery keys' in the device menu to see the list of encrypted drives on the device³.

**For Intune:**
1. **Company Portal Website:**
   - Sign in to the Company Portal website on any device.
2. **Locate the Device:**
   - Go to 'Devices' and select the PC you need the recovery key for.
3. **Show Recovery Key:**
   - Click on 'Show recovery key' to display the BitLocker recovery key. For security reasons, the key disappears after five minutes. To view it again, select 'Show recovery key'².

Remember, the recovery key is a 48-character long password divided into eight groups of 6 characters separated by dashes. It's essential to handle this information securely and ensure that only authorized personnel have access to it. If you're deploying this as part of an image, include these steps in your deployment task sequence or app configuration to automate the process. Always test thoroughly before rolling out to your environment.

Source: Conversation with Copilot, 20/07/2024
(1) Tenant attach - BitLocker recovery keys - Configuration Manager. https://learn.microsoft.com/en-us/mem/configmgr/tenant-attach/bitlocker-recovery-keys.
(2) Get BitLocker recovery key for enrolled device | Microsoft Learn. https://learn.microsoft.com/en-us/mem/intune/user-help/get-recovery-key-windows.
(3) Using BitLocker recovery keys with Microsoft Endpoint Manager .... https://techcommunity.microsoft.com/t5/intune-customer-success/using-bitlocker-recovery-keys-with-microsoft-endpoint-manager/ba-p/2255517.
(4) How to configure BitLocker on Windows devices using Intune. https://www.manishbangia.com/how-to-configure-bitlocker-on-windows-devices-using-intune/.
(5) Creating and deployment images using SCCM (Step by Step). https://www.youtube.com/watch?v=lpsUbaboULc.
(6) Setup and configure the SCCM Client in Microsoft Intune. https://www.youtube.com/watch?v=4gZ80ihKeJQ.
(7) How to Create, Manage, and Deploy Applications in Microsoft SCCM (EXE and MSI Installs). https://www.youtube.com/watch?v=G4iyyq_UlDA.
(8) Migration guide to Microsoft Intune | Microsoft Learn. https://learn.microsoft.com/en-us/mem/intune/fundamentals/deployment-guide-intune-setup.
(9) Add a Windows 10 operating system image using Configuration Manager .... https://learn.microsoft.com/en-us/windows/deployment/deploy-windows-cm/add-a-windows-10-operating-system-image-using-configuration-manager.
(10) Windows 10 Deployment | Create SCCM Windows 10 Build and Capture Task .... https://www.systemcenterdudes.com/sccm-windows-10-build-and-capture-task-sequence/.
(11) WinPE: Adding Windows PowerShell support to Windows PE. https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/winpe-adding-powershell-support-to-windows-pe?view=windows-11.
(12) How To Create A Custom WinPE Boot Image With PowerShell Support # .... https://charbelnemnom.com/how-to-create-a-custom-winpe-boot-image-with-powershell-support-powershell-deploy-windowsserver/.
(13) How to Create a PowerShell Script. https://www.youtube.com/watch?v=gjxKFkauhOg.
(14) How to execute a PowerShell Script. https://www.youtube.com/watch?v=PN-yTpJDNYs.
(15) How to Run a PowerShell Script From the Command Line and More. https://www.youtube.com/watch?v=s3sWPUBLxmc.
(16) GitHub - shannonfritz/Make-UEFIUSB: Create a Bootable USB drive for .... https://github.com/shannonfritz/Make-UEFIUSB.
(17) Building .ISO files using Powershell for a Secured Environment. https://www.checkyourlogs.net/building-iso-files-using-powershell-for-a-secured-environment/.
(18) WinPE auto scripts - Stack Overflow. https://stackoverflow.com/questions/10906990/winpe-auto-scripts.
