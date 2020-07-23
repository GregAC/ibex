import sys
import re
import PIL
import PIL.Image
import io

frame_re = re.compile(r'Frame:\s*(\d+)')

def read_frame(lines, pixels):
    img_data  = []
    frame_num = 0
    try:
        frame_re_match = frame_re.search(next(lines))


        if not frame_re_match:
            return (0, None)

        frame_num = int(frame_re_match.group(1))

        cur_x = 0
        cur_y = 0

        for i in range(pixels):
            pix = next(lines)
            pix_r = int(pix[0:2], 16)
            pix_g = int(pix[2:4], 16)
            pix_b = int(pix[4:6], 16)

            img_data.append(pix_r)
            img_data.append(pix_g)
            img_data.append(pix_b)


    except StopIteration:
        return (0, None)

    return frame_num, img_data

display_in = open(sys.argv[1], 'r')
display_in_iter = iter(display_in)
frame_width = int(sys.argv[2])
frame_height = int(sys.argv[3])
display_out_base = sys.argv[4]

print(f'Reading data from {sys.argv[1]} producing {frame_width} x {frame_height} images with basename {display_out_base}')

while True:
    frame_num, img_data = read_frame(display_in_iter, frame_width * frame_height)
    if img_data:
        frame_out = PIL.Image.frombytes("RGB",
                                        (frame_width, frame_height),
                                        bytes(img_data),
                                        "raw",
                                        "RGB")
        output_name = f'{display_out_base}_{frame_num}.png'
        print(f'Got frame {frame_num}, outputting to {output_name}')
        frame_out.save(output_name)
    else:
        break

