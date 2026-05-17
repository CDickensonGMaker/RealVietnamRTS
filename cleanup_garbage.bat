@echo off
cd /d "C:\Users\caleb\RealVietnamRTS\terrain\systems"
for %%f in (*cp*) do (
    echo Deleting: %%f
    del "%%f"
)
cd /d "C:\Users\caleb\RealVietnamRTS\terrain\water"
for %%f in (*cp*) do (
    echo Deleting: %%f
    del "%%f"
)
echo Done.
