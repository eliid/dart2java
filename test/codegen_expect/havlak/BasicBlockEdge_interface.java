package havlak;

public interface BasicBlockEdge_interface extends dart._runtime.base.DartObject_interface
{
  havlak.BasicBlock_interface getFrom();
  havlak.BasicBlock_interface getTo();
  havlak.BasicBlock_interface setFrom(havlak.BasicBlock_interface value);
  havlak.BasicBlock_interface setTo(havlak.BasicBlock_interface value);
  void _constructor(havlak.CFG_interface cfg, int fromName, int toName);
}
