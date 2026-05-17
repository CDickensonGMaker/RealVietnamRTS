import os

terrain_path = r"C:\Users\caleb\RealVietnamRTS\terrain"

for root, dirs, files in os.walk(terrain_path):
    for f in files:
        if "&&" in f or " cp " in f:
            full_path = os.path.join(root, f)
            try:
                os.remove(full_path)
            except:
                pass

print("Done!")
