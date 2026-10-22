U0 DBOptPass(CCmpCtrl *cc)
{
  CIntermediateCode *tmpi=cc->coc.coc_head.next;
  while (tmpi->ic_code)
    tmpi=tmpi->next;
}
