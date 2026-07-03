FROM mcr.microsoft.com/dotnet/runtime:10.0
ARG PS_VERSION=7.6.3
ARG SLEET_VERSION=7.1.0
# ENV SLEET_FEED_TYPE=
# ENV SLEET_FEED_CONTAINER=
# ENV SLEET_FEED_PATH=
# ENV AZURE_TENANT_ID=
# ENV AZURE_CLIENT_ID=
# ENV AZURE_CLIENT_SECRET=

ENV DOTNET_SYSTEM_GLOBALIZATION_PREDEFINED_CULTURES_ONLY=1

RUN ln -s /home/app/pwsh/pwsh /usr/bin/pwsh
RUN ln -s /home/app/sleet/sleet /usr/bin/sleet

#Get PowerShell
USER app
WORKDIR /home/app

ADD --chown=app:app https://github.com/PowerShell/PowerShell/releases/download/v${PS_VERSION}/powershell-${PS_VERSION}-linux-x64-fxdependent.tar.gz /home/app
RUN <<SCRIPT
mkdir pwsh
tar -xzf powershell-${PS_VERSION}-linux-x64-fxdependent.tar.gz -C pwsh
chmod +x pwsh/pwsh
rm powershell-${PS_VERSION}-linux-x64-fxdependent.tar.gz
SCRIPT


SHELL ["/usr/bin/pwsh", "-NoProfile", "-Command"]

RUN <<SCRIPT
iwr bit.ly/modulefast | iex
Install-ModuleFast AzAuth
SCRIPT

RUN <<SCRIPT
"Installing Sleet in $PWD"
New-Item -ItemType Directory sleetTemp
Invoke-WebRequest "https://www.nuget.org/api/v2/package/Sleet/$($ENV:SLEET_VERSION)" -OutFile Sleet.zip
New-Item -ItemType Directory sleet
Expand-Archive Sleet.zip sleetTemp
Copy-Item -Path sleetTemp/tools/net10.0/any/* -Destination sleet -Recurse -Verbose
Remove-Item sleetTemp -Recurse -Force
SCRIPT

ADD --chown=app:app --chmod=755 Docker/sleet /home/app/sleet/sleet


ADD --chown=app:app Modules/AzBlob /home/app/.local/share/powershell/Modules/AzBlob
ADD --chown=app:app --chmod=755 GallerySync.ps1 /home/app

CMD [ "/home/app/GallerySync.ps1" ]