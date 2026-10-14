import sys
from PIL import Image
import rooms, font
PAL=[0x000000,0xFFFFFF,0x68372B,0x70A4B2,0x6F3D86,0x588D43,0x352879,0xB8C76F,0x6F4F25,0x433900,0x9A6759,0x444444,0x6C6C6C,0x9AD284,0x6C5EB5,0x959595]
def rgb(c): c=PAL[c]; return ((c>>16)&255,(c>>8)&255,c&255)
D022,D023=9,0
def render_room(i, grid, tb, co, sky=14):
    im=Image.new('RGB',(320,160))
    for cy in range(20):
        for cx in range(40):
            code=grid[cy*40+cx]
            if code<rooms.FIRST_TILE:
                col=rooms.ROOM_TEXT_COL[i]
                rows=font.glyph_bytes(code)
                for y in range(8):
                    for x in range(8):
                        im.putpixel((cx*8+x,cy*8+y), rgb(col) if rows[y]>>(7-x)&1 else rgb(sky))
            else:
                rows=tb[code]; col=co[code]&7
                for y in range(8):
                    for x in range(4):
                        v=(rows[y]>>(6-2*x))&3
                        c=[sky,D022,D023,col][v]
                        im.putpixel((cx*8+2*x,cy*8+y),rgb(c)); im.putpixel((cx*8+2*x+1,cy*8+y),rgb(c))
    return im
if __name__=="__main__":
    big=Image.new('RGB',(320,164*5))
    for i in range(5):
        tb,co,g,cg,og,n=rooms.build_room(i)
        print(rooms.ROOM_NAMES[i],n)
        big.paste(render_room(i,g,tb,co,sky=14 if i!=4 else 14),(0,i*164))
    big.resize((640,big.height*2),Image.NEAREST).save('../rooms_preview.png')
