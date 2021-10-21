#[derive(Clone, Copy)]
pub struct HartMask {
    pub mask: usize,
    pub mask_base: usize,
}

impl HartMask {
    pub fn new(mask: usize, mask_base: usize) -> Self {
        Self { mask, mask_base }
    }

    pub fn is_set(&self, hart_id: usize) -> bool {
        match hart_id.checked_sub(self.mask_base) {
            None => false,
            Some(v) => {
                if v < core::mem::size_of::<usize>() * 8 {
                    (self.mask >> v) & 1 != 0
                } else {
                    false
                }
            }
        }
    }

    pub fn normalize(&self) -> usize {
        let mut ret = 0;
        for i in 0..4 {
            ret |= (self.is_set(i) as usize) << i;
        }
        ret
    }
}
