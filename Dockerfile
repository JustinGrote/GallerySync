FROM mcr.microsoft.com/powershell:7.4-mariner-2.0
SHELL [ "pwsh", "--noninteractive", "--command" ]

ARG SLEET_VERSION=6.1.0
# ENV SLEET_FEED_TYPE=
# ENV SLEET_FEED_CONTAINER=
# ENV SLEET_FEED_PATH=
# ENV AZURE_TENANT_ID=
# ENV AZURE_CLIENT_ID=
# ENV AZURE_CLIENT_SECRET=

# Install Sleet, which doesn't have a Linux standalone executable
RUN Install-PSResource AzAuth -Version 2.3.0 -TrustRepository -Confirm:$false
ADD Modules/AzBlob /usr/local/share/powershell/Modules/AzBlob
RUN <<EOF
mkdir /sleetTemp
Push-Location /sleetTemp
Invoke-WebRequest "https://www.nuget.org/api/v2/package/Sleet/$($ENV:SLEET_VERSION)" -OutFile Sleet.zip
Expand-Archive Sleet.zip
Move-Item ./Sleet/tools/net8.0/any /sleet
Pop-Location
Remove-Item /sleetTemp -Recurse -Force
EOF

ADD Docker/sleet /usr/local/bin
RUN chmod +x /usr/local/bin/sleet

ADD GallerySync.ps1 /
RUN chmod +x /GallerySync.ps1
WORKDIR /work
CMD [ "/GallerySync.ps1" ]