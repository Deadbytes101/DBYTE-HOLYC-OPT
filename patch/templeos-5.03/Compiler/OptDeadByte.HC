#define DBYTE_OPT_MAX_IC	1048576

Bool dbyte_opt_enable=FALSE;

Bool OptDeadByteVerify(CCmpCtrl *cc)
{
  CIntermediateCode *tmpi;
  I64 count=0;

  if (!cc)
    return FALSE;

  tmpi=cc->coc.coc_head.next;
  if (!tmpi)
    return FALSE;

  while (tmpi->ic_code) {
    if (!tmpi->next || !tmpi->last)
      return FALSE;
    if (tmpi->next->last!=tmpi || tmpi->last->next!=tmpi)
      return FALSE;
    if (++count>DBYTE_OPT_MAX_IC)
      return FALSE;
    tmpi=tmpi->next;
  }

  if (!tmpi->next || !tmpi->last)
    return FALSE;
  if (tmpi->next->last!=tmpi || tmpi->last->next!=tmpi)
    return FALSE;
  if (tmpi!=&cc->coc.coc_head.next)
    return FALSE;

  return TRUE;
}

U0 OptDeadByteGate(CCmpCtrl *cc)
{
  if (!OptDeadByteVerify(cc))
    LexExcept(cc,"DBYTE optimizer IC list failure at ");

  if (!dbyte_opt_enable)
    return;

  // No rewrite is authorized in the foundation build.

  if (!OptDeadByteVerify(cc))
    LexExcept(cc,"DBYTE optimizer post-pass failure at ");
}
