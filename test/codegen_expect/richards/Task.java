package richards;

public abstract class Task extends dart._runtime.base.DartObject implements richards.Task_interface
{
    public static dart._runtime.types.simple.InterfaceTypeInfo dart2java$typeInfo = new dart._runtime.types.simple.InterfaceTypeInfo(richards.Task.class, richards.Task_interface.class);
    private static dart._runtime.types.simple.InterfaceTypeExpr dart2java$typeExpr_Object = new dart._runtime.types.simple.InterfaceTypeExpr(dart._runtime.helpers.ObjectHelper.dart2java$typeInfo);
    static {
      richards.Task.dart2java$typeInfo.superclass = dart2java$typeExpr_Object;
    }
    public richards.Scheduler_interface scheduler;
  
    public Task(dart._runtime.helpers.ConstructorHelper.EmptyConstructorMarker arg, dart._runtime.types.simple.Type type)
    {
      super(arg, type);
    }
  
    public abstract richards.TaskControlBlock_interface run(richards.Packet_interface packet);
    public void _constructor(richards.Scheduler_interface scheduler)
    {
      final dart._runtime.types.simple.TypeEnvironment dart2java$localTypeEnv = this.dart2java$type.env;
      this.scheduler = scheduler;
      super._constructor();
    }
    public richards.Scheduler_interface getScheduler()
    {
      return this.scheduler;
    }
    public richards.Scheduler_interface setScheduler(richards.Scheduler_interface value)
    {
      this.scheduler = value;
      return value;
    }
}
