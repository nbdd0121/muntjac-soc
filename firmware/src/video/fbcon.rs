use byteorder::{ByteOrder, LE};
use core::fmt::Write;

pub struct Framebuffer<'a> {
    pub framebuffer: &'a mut [u8],
    pub width: u32,
    pub height: u32,
    pub bpl: u32,
    pub bpp: u32,
}

pub struct Fbcon<'a> {
    framebuffer: Framebuffer<'a>,
    x: u32,
    y: u32,
    font: psf2::Font<&'static [u8]>,
}

impl<'a> Write for Fbcon<'a> {
    fn write_str(&mut self, s: &str) -> core::fmt::Result {
        for c in s.chars() {
            if c == '\n' {
                self.write_raw_char('\r');
            }
            self.write_raw_char(c);
        }
        Ok(())
    }
}

impl<'a> Fbcon<'a> {
    pub fn new(framebuffer: Framebuffer<'a>) -> Self {
        Self {
            framebuffer,
            x: 0,
            y: 0,
            font: psf2::Font::new(&include_bytes!("../../../data/bizcat.psf")[..]).unwrap(),
        }
    }

    pub fn write_raw_char(&mut self, c: char) {
        // Handle special characters
        match c {
            '\x1C' => {
                // Clear screen
                self.x = 0;
                self.y = 0;
                self.framebuffer.framebuffer.iter_mut().for_each(|x| *x = 0);
                return;
            }
            '\r' => {
                // Carriage return
                self.x = 0;
                return;
            }
            '\n' => {
                // Newline
                self.y += self.font.height();
                return;
            }
            _ => (),
        }

        if self.x + self.font.width() > self.framebuffer.width {
            self.x = 0;
            self.y += self.font.height();
        }

        if self.y + self.font.height() > self.framebuffer.height {
            let scroll_amount = self.y + self.font.height() - self.framebuffer.height;
            self.framebuffer
                .framebuffer
                .copy_within((scroll_amount * self.framebuffer.bpl) as usize.., 0);
        }

        let glyph = c.try_into().ok().and_then(|x| self.font.get_ascii(x));
        let glyph = glyph.unwrap_or_else(|| self.font.get_ascii(b'?').unwrap());
        let mut data = glyph.data();
        let mut line_start = self.framebuffer.bpl * self.y + self.x * self.framebuffer.bpp;
        for _ in 0..self.font.height() {
            let mut fb_ptr = line_start;
            for a in 0..self.font.width() as usize {
                if data[a / 8] & (1 << (7 - a % 8)) != 0 {
                    match self.framebuffer.bpp {
                        2 => LE::write_u16(
                            &mut self.framebuffer.framebuffer[fb_ptr as usize..],
                            0xFFFF,
                        ),
                        4 => LE::write_u32(
                            &mut self.framebuffer.framebuffer[fb_ptr as usize..],
                            0xFFFFFFFF,
                        ),
                        _ => unreachable!(),
                    }
                } else {
                    match self.framebuffer.bpp {
                        2 => LE::write_u16(
                            &mut self.framebuffer.framebuffer[fb_ptr as usize..],
                            0x0000,
                        ),
                        4 => LE::write_u32(
                            &mut self.framebuffer.framebuffer[fb_ptr as usize..],
                            0x00000000,
                        ),
                        _ => unreachable!(),
                    }
                }
                fb_ptr += self.framebuffer.bpp;
            }
            data = &data[(self.font.width() as usize + 7) / 8..];
            line_start += self.framebuffer.bpl;
        }

        self.x += self.font.width();
    }
}
