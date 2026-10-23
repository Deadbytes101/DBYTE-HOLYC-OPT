// Conservative pass 6.5. The original HolyC backend stays in control.
// Remove pure 64-bit register identity moves, then adjacent dead writes.
// Do not change stack/cvt/trace flags or the original x86-64 backend.
// Both rewrites require exact integer reg-to-reg operands.
U0 DBOptPass(CCmpCtrl *cc)
{
  CIntermediateCode *tmpi=cc->coc.coc_head.next;
  while (tmpi->ic_code) {
    if (tmpi->ic_code==IC_MOV &&
        tmpi->ic_flags==ICF_USE_INT &&
        tmpi->arg1.type==MDF_REG+RT_I64 &&
        tmpi->res.type==MDF_REG+RT_I64 &&
        !tmpi->arg2.type.mode &&
        !tmpi->arg1.disp && !tmpi->res.disp &&
        !tmpi->ic_data &&
        tmpi->arg1.reg<REG_REGS_NUM &&
        tmpi->res.reg<REG_REGS_NUM &&
        tmpi->res.reg!=REG_RSP &&
        tmpi->res.reg!=REG_RBP &&
        tmpi->arg1.reg==tmpi->res.reg)
      OptSetNOP1(tmpi);
    else if (tmpi->ic_code==IC_MOV &&
        tmpi->next->ic_code==IC_MOV &&
        tmpi->ic_flags==ICF_USE_INT &&
        tmpi->next->ic_flags==ICF_USE_INT &&
        tmpi->arg1.type==MDF_REG+RT_I64 &&
        tmpi->res.type==MDF_REG+RT_I64 &&
        tmpi->next->arg1.type==MDF_REG+RT_I64 &&
        tmpi->next->res.type==MDF_REG+RT_I64 &&
        !tmpi->arg2.type.mode &&
        !tmpi->next->arg2.type.mode &&
        !tmpi->arg1.disp && !tmpi->res.disp &&
        !tmpi->next->arg1.disp && !tmpi->next->res.disp &&
        !tmpi->ic_data && !tmpi->next->ic_data &&
        tmpi->arg1.reg<REG_REGS_NUM &&
        tmpi->next->arg1.reg<REG_REGS_NUM &&
        tmpi->res.reg<REG_REGS_NUM &&
        tmpi->res.reg!=REG_RSP &&
        tmpi->res.reg!=REG_RBP &&
        tmpi->arg1.reg!=tmpi->res.reg &&
        tmpi->res.reg==tmpi->next->res.reg &&
        tmpi->next->arg1.reg!=tmpi->next->res.reg)
      OptSetNOP1(tmpi);
    // Experimental R20: source and target stay unchanged across a
    // single unrelated pure register move. Third copy is redundant.
    // All three must be exact I64 register operations without flags
    // other than USE_INT. Do not touch stack/frame/trace operations.
    else if (tmpi->ic_code==IC_MOV &&
        tmpi->next->ic_code==IC_MOV &&
        tmpi->next->next->ic_code==IC_MOV &&
        tmpi->ic_flags==ICF_USE_INT &&
        tmpi->next->ic_flags==ICF_USE_INT &&
        tmpi->next->next->ic_flags==ICF_USE_INT &&
        tmpi->arg1.type==MDF_REG+RT_I64 &&
        tmpi->res.type==MDF_REG+RT_I64 &&
        tmpi->next->arg1.type==MDF_REG+RT_I64 &&
        tmpi->next->res.type==MDF_REG+RT_I64 &&
        tmpi->next->next->arg1.type==MDF_REG+RT_I64 &&
        tmpi->next->next->res.type==MDF_REG+RT_I64 &&
        !tmpi->arg2.type.mode &&
        !tmpi->next->arg2.type.mode &&
        !tmpi->next->next->arg2.type.mode &&
        !tmpi->arg1.disp && !tmpi->res.disp &&
        !tmpi->next->arg1.disp && !tmpi->next->res.disp &&
        !tmpi->next->next->arg1.disp &&
        !tmpi->next->next->res.disp &&
        !tmpi->ic_data && !tmpi->next->ic_data &&
        !tmpi->next->next->ic_data &&
        tmpi->arg1.reg<REG_REGS_NUM &&
        tmpi->res.reg<REG_REGS_NUM &&
        tmpi->next->arg1.reg<REG_REGS_NUM &&
        tmpi->next->res.reg<REG_REGS_NUM &&
        tmpi->arg1.reg!=REG_RSP &&
        tmpi->arg1.reg!=REG_RBP &&
        tmpi->res.reg!=REG_RSP &&
        tmpi->res.reg!=REG_RBP &&
        tmpi->next->arg1.reg!=REG_RSP &&
        tmpi->next->arg1.reg!=REG_RBP &&
        tmpi->next->res.reg!=REG_RSP &&
        tmpi->next->res.reg!=REG_RBP &&
        tmpi->arg1.reg!=tmpi->res.reg &&
        tmpi->next->arg1.reg!=tmpi->next->res.reg &&
        tmpi->next->res.reg!=tmpi->arg1.reg &&
        tmpi->next->res.reg!=tmpi->res.reg &&
        tmpi->arg1.reg==tmpi->next->next->arg1.reg &&
        tmpi->res.reg==tmpi->next->next->res.reg)
      OptSetNOP1(tmpi->next->next);
    tmpi=tmpi->next;
  }
}
