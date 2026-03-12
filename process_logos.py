from PIL import Image, ImageOps
import os

def process_logo(input_path, output_path, canvas_size, logo_size, bg_color=(255, 255, 255)):
    # Open source logo
    logo = Image.open(input_path).convert("RGBA")
    
    # Trim transparency if any to get the core logo
    if logo.mode == 'RGBA':
        bbox = logo.getbbox()
        if bbox:
            logo = logo.crop(bbox)
            
    # Resize logo to fit logo_size
    logo.thumbnail((logo_size, logo_size), Image.Resampling.LANCZOS)
    
    # Create canvas
    canvas = Image.new("RGBA" if bg_color is None else "RGB", (canvas_size, canvas_size), bg_color or (0,0,0,0))
    
    # Calculate position to center
    pos = ((canvas_size - logo.width) // 2, (canvas_size - logo.height) // 2)
    
    # Paste logo
    if logo.mode == 'RGBA':
        canvas.paste(logo, pos, logo)
    else:
        canvas.paste(logo, pos)
        
    # Save
    canvas.save(output_path)
    print(f"Saved {output_path}")

base_dir = r"c:\Users\waray\Music\SmartClassroom_montoring"
input_logo = os.path.join(base_dir, "assets", "images", "logo.png")

# NEW Launcher format based on user request (1024x1024 canvas, ~780x780 logo)
process_logo(input_logo, os.path.join(base_dir, "assets", "images", "logo_launcher.png"), 1024, 780)

# Overwrite main logo with a clean centered version for UI as well
process_logo(input_logo, os.path.join(base_dir, "assets", "images", "logo.png"), 512, 400)
