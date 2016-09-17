package havlak;

public class HavlakLoopFinder extends dart._runtime.base.DartObject implements havlak.HavlakLoopFinder_interface
{
    public static dart._runtime.types.simple.InterfaceTypeInfo dart2java$typeInfo = new dart._runtime.types.simple.InterfaceTypeInfo(havlak.HavlakLoopFinder.class, havlak.HavlakLoopFinder_interface.class);
    private static dart._runtime.types.simple.InterfaceTypeExpr dart2java$typeExpr_UnionFindNode = new dart._runtime.types.simple.InterfaceTypeExpr(havlak.UnionFindNode.dart2java$typeInfo);
    private static dart._runtime.types.simple.InterfaceTypeExpr dart2java$typeExpr_Object = new dart._runtime.types.simple.InterfaceTypeExpr(dart._runtime.helpers.ObjectHelper.dart2java$typeInfo);
    static {
      havlak.HavlakLoopFinder.dart2java$typeInfo.superclass = dart2java$typeExpr_Object;
    }
    static {
      final dart._runtime.types.simple.TypeEnvironment dart2java$localTypeEnv = dart._runtime.types.simple.TypeEnvironment.ROOT;
      havlak.HavlakLoopFinder.BB_TOP = 0;
      havlak.HavlakLoopFinder.BB_NONHEADER = 1;
      havlak.HavlakLoopFinder.BB_REDUCIBLE = 2;
      havlak.HavlakLoopFinder.BB_SELF = 3;
      havlak.HavlakLoopFinder.BB_IRREDUCIBLE = 4;
      havlak.HavlakLoopFinder.BB_DEAD = 5;
      havlak.HavlakLoopFinder.BB_LAST = 6;
      havlak.HavlakLoopFinder.UNVISITED = (-1);
      havlak.HavlakLoopFinder.MAXNONBACKPREDS = (32 * 1024);
    }
    public havlak.CFG_interface cfg;
    public havlak.LSG_interface lsg;
    public static int BB_TOP;
    public static int BB_NONHEADER;
    public static int BB_REDUCIBLE;
    public static int BB_SELF;
    public static int BB_IRREDUCIBLE;
    public static int BB_DEAD;
    public static int BB_LAST;
    public static int UNVISITED;
    public static int MAXNONBACKPREDS;
  
    public HavlakLoopFinder(dart._runtime.helpers.ConstructorHelper.EmptyConstructorMarker arg, dart._runtime.types.simple.Type type)
    {
      super(arg, type);
    }
  
    public boolean isAncestor(int w, int v, dart.core.List_interface<java.lang.Integer> last)
    {
      final dart._runtime.types.simple.TypeEnvironment dart2java$localTypeEnv = this.dart2java$type.env;
      return ((w <= v) && (v <= last.operatorAt(w)));
    }
    public int DFS(havlak.BasicBlock_interface currentNode, dart.core.List_interface<havlak.UnionFindNode_interface> nodes, dart.core.List_interface<java.lang.Integer> number, dart.core.List_interface<java.lang.Integer> last, int current)
    {
      final dart._runtime.types.simple.TypeEnvironment dart2java$localTypeEnv = this.dart2java$type.env;
      nodes.operatorAt(current).initNode(currentNode, current);
      number.operatorAtPut(currentNode.getName(), current);
      int lastid = current;
      for (int target = 0; (target < currentNode.getOutEdges().getLength()); target = (target + 1))
      {
        if ((number.operatorAt(currentNode.getOutEdges().operatorAt(target).getName()) == havlak.HavlakLoopFinder.UNVISITED))
        {
          lastid = this.DFS(currentNode.getOutEdges().operatorAt(target), ((dart.core.List_interface) nodes), ((dart.core.List_interface) number), ((dart.core.List_interface) last), (lastid + 1));
        }
      }
      last.operatorAtPut(number.operatorAt(currentNode.getName()), lastid);
      return lastid;
    }
    public int findLoops()
    {
      final dart._runtime.types.simple.TypeEnvironment dart2java$localTypeEnv = this.dart2java$type.env;
      if (dart._runtime.helpers.ObjectHelper.operatorEqual(this.getCfg().getStartNode(), null))
      {
        return 0;
      }
      int size = this.getCfg().getNumNodes();
      dart.core.List_interface<dart.core.List_interface<java.lang.Integer>> nonBackPreds = ((dart.core.List_interface) dart.core.List.factory$(dart.core.List_interface.class, size));
      dart.core.List_interface<dart.core.List_interface<java.lang.Integer>> backPreds = ((dart.core.List_interface) dart.core.List.factory$(dart.core.List_interface.class, size));
      dart.core.List_interface<java.lang.Integer> number = ((dart.core.List_interface) dart.core.List.factory$(java.lang.Integer.class, size));
      dart.core.List_interface<java.lang.Integer> header = ((dart.core.List_interface) dart.core.List.factory$(java.lang.Integer.class, size));
      dart.core.List_interface<java.lang.Integer> types = ((dart.core.List_interface) dart.core.List.factory$(java.lang.Integer.class, size));
      dart.core.List_interface<java.lang.Integer> last = ((dart.core.List_interface) dart.core.List.factory$(java.lang.Integer.class, size));
      dart.core.List_interface<havlak.UnionFindNode_interface> nodes = ((dart.core.List_interface) dart.core.List.factory$(havlak.UnionFindNode_interface.class, size));
      for (int i = 0; (i < size); i = (i + 1))
      {
        nonBackPreds.operatorAtPut(i, dart._runtime.base.DartList.Generic._fromArguments(java.lang.Integer.class));
        backPreds.operatorAtPut(i, dart._runtime.base.DartList.Generic._fromArguments(java.lang.Integer.class));
        number.operatorAtPut(i, havlak.HavlakLoopFinder.UNVISITED);
        header.operatorAtPut(i, 0);
        types.operatorAtPut(i, havlak.HavlakLoopFinder.BB_NONHEADER);
        last.operatorAtPut(i, 0);
        nodes.operatorAtPut(i, ((havlak.UnionFindNode_interface) havlak.UnionFindNode._new(dart2java$localTypeEnv.evaluate(dart2java$typeExpr_UnionFindNode))));
      }
      this.DFS(this.getCfg().getStartNode(), ((dart.core.List_interface) nodes), ((dart.core.List_interface) number), ((dart.core.List_interface) last), 0);
      for (int w = 0; (w < size); w = (w + 1))
      {
        havlak.BasicBlock_interface nodeW = nodes.operatorAt(w).getBb();
        if (dart._runtime.helpers.ObjectHelper.operatorEqual(nodeW, null))
        {
          types.operatorAtPut(w, havlak.HavlakLoopFinder.BB_DEAD);
        }
        else
        {
          if ((nodeW.getNumPred() > 0))
          {
            for (int nv = 0; (nv < nodeW.getInEdges().getLength()); nv = (nv + 1))
            {
              havlak.BasicBlock_interface nodeV = nodeW.getInEdges().operatorAt(nv);
              int v = number.operatorAt(nodeV.getName());
              if ((!(v == havlak.HavlakLoopFinder.UNVISITED)))
              {
                if (this.isAncestor(w, v, ((dart.core.List_interface) last)))
                {
                  backPreds.operatorAt(w).add(v);
                }
                else
                {
                  nonBackPreds.operatorAt(w).add(v);
                }
              }
            }
          }
        }
      }
      for (int w = (size - 1); (w >= 0); w = (w - 1))
      {
        __codeLabel_0: {
          dart.core.List_interface<havlak.UnionFindNode_interface> nodePool = ((dart.core.List_interface) dart._runtime.base.DartList.Generic._fromArguments(havlak.UnionFindNode_interface.class));
          havlak.BasicBlock_interface nodeW = nodes.operatorAt(w).getBb();
          if (dart._runtime.helpers.ObjectHelper.operatorEqual(nodeW, null))
          {
            break __codeLabel_0;
          }
          for (int vi = 0; (vi < backPreds.operatorAt(w).getLength()); vi = (vi + 1))
          {
            int v = backPreds.operatorAt(w).operatorAt(vi);
            if ((!(v == w)))
            {
              nodePool.add(nodes.operatorAt(v).findSet());
            }
            else
            {
              types.operatorAtPut(w, havlak.HavlakLoopFinder.BB_SELF);
            }
          }
          dart.core.List_interface<havlak.UnionFindNode_interface> workList = ((dart.core.List_interface) dart._runtime.base.DartList.Generic._fromArguments(havlak.UnionFindNode_interface.class));
          for (int n = 0; (n < nodePool.getLength()); n = (n + 1))
          {
            workList.add(nodePool.operatorAt(n));
          }
          if ((!(nodePool.getLength() == 0)))
          {
            types.operatorAtPut(w, havlak.HavlakLoopFinder.BB_REDUCIBLE);
          }
          while ((workList.getLength() > 0))
          {
            havlak.UnionFindNode_interface x = workList.removeAt(0);
            int nonBackSize = nonBackPreds.operatorAt(x.getDfsNumber()).getLength();
            if ((nonBackSize > havlak.HavlakLoopFinder.MAXNONBACKPREDS))
            {
              return 0;
            }
            for (int iter = 0; (iter < nonBackPreds.operatorAt(x.getDfsNumber()).getLength()); iter = (iter + 1))
            {
              havlak.UnionFindNode_interface y = nodes.operatorAt(nonBackPreds.operatorAt(x.getDfsNumber()).operatorAt(iter));
              havlak.UnionFindNode_interface ydash = y.findSet();
              if ((!this.isAncestor(w, ydash.getDfsNumber(), ((dart.core.List_interface) last))))
              {
                types.operatorAtPut(w, havlak.HavlakLoopFinder.BB_IRREDUCIBLE);
                nonBackPreds.operatorAt(w).add(ydash.getDfsNumber());
              }
              else
              {
                if ((!(ydash.getDfsNumber() == w)))
                {
                  if ((nodePool.indexOf(ydash, 0) == (-1)))
                  {
                    workList.add(ydash);
                    nodePool.add(ydash);
                  }
                }
              }
            }
          }
          if (((nodePool.getLength() > 0) || (types.operatorAt(w) == havlak.HavlakLoopFinder.BB_SELF)))
          {
            havlak.SimpleLoop_interface loop = this.getLsg().createNewLoop();
            loop.setHeader_(nodeW);
            if ((types.operatorAt(w) == havlak.HavlakLoopFinder.BB_IRREDUCIBLE))
            {
              loop.setIsReducible(true);
            }
            else
            {
              loop.setIsReducible(false);
            }
            nodes.operatorAt(w).setLoop(loop);
            for (int np = 0; (np < nodePool.getLength()); np = (np + 1))
            {
              havlak.UnionFindNode_interface node = nodePool.operatorAt(np);
              header.operatorAtPut(node.getDfsNumber(), w);
              node.union(nodes.operatorAt(w));
              if ((!dart._runtime.helpers.ObjectHelper.operatorEqual(node.getLoop(), null)))
              {
                node.getLoop().setParent_(loop);
              }
              else
              {
                loop.addNode(node.getBb());
              }
            }
            this.getLsg().addLoop(loop);
          }
        }
      }
      return this.getLsg().getNumLoops();
    }
    public void _constructor(havlak.CFG_interface cfg, havlak.LSG_interface lsg)
    {
      final dart._runtime.types.simple.TypeEnvironment dart2java$localTypeEnv = this.dart2java$type.env;
      this.cfg = cfg;
      this.lsg = lsg;
      super._constructor();
    }
    public havlak.CFG_interface getCfg()
    {
      return this.cfg;
    }
    public havlak.LSG_interface getLsg()
    {
      return this.lsg;
    }
    public static int getBB_TOP()
    {
      return havlak.HavlakLoopFinder.BB_TOP;
    }
    public static int getBB_NONHEADER()
    {
      return havlak.HavlakLoopFinder.BB_NONHEADER;
    }
    public static int getBB_REDUCIBLE()
    {
      return havlak.HavlakLoopFinder.BB_REDUCIBLE;
    }
    public static int getBB_SELF()
    {
      return havlak.HavlakLoopFinder.BB_SELF;
    }
    public static int getBB_IRREDUCIBLE()
    {
      return havlak.HavlakLoopFinder.BB_IRREDUCIBLE;
    }
    public static int getBB_DEAD()
    {
      return havlak.HavlakLoopFinder.BB_DEAD;
    }
    public static int getBB_LAST()
    {
      return havlak.HavlakLoopFinder.BB_LAST;
    }
    public static int getUNVISITED()
    {
      return havlak.HavlakLoopFinder.UNVISITED;
    }
    public static int getMAXNONBACKPREDS()
    {
      return havlak.HavlakLoopFinder.MAXNONBACKPREDS;
    }
    public static int setBB_TOP(int value)
    {
      havlak.HavlakLoopFinder.BB_TOP = value;
      return value;
    }
    public static int setBB_NONHEADER(int value)
    {
      havlak.HavlakLoopFinder.BB_NONHEADER = value;
      return value;
    }
    public static int setBB_REDUCIBLE(int value)
    {
      havlak.HavlakLoopFinder.BB_REDUCIBLE = value;
      return value;
    }
    public static int setBB_SELF(int value)
    {
      havlak.HavlakLoopFinder.BB_SELF = value;
      return value;
    }
    public static int setBB_IRREDUCIBLE(int value)
    {
      havlak.HavlakLoopFinder.BB_IRREDUCIBLE = value;
      return value;
    }
    public static int setBB_DEAD(int value)
    {
      havlak.HavlakLoopFinder.BB_DEAD = value;
      return value;
    }
    public static int setBB_LAST(int value)
    {
      havlak.HavlakLoopFinder.BB_LAST = value;
      return value;
    }
    public static int setUNVISITED(int value)
    {
      havlak.HavlakLoopFinder.UNVISITED = value;
      return value;
    }
    public static int setMAXNONBACKPREDS(int value)
    {
      havlak.HavlakLoopFinder.MAXNONBACKPREDS = value;
      return value;
    }
    public static havlak.HavlakLoopFinder_interface _new(dart._runtime.types.simple.Type type, havlak.CFG_interface cfg, havlak.LSG_interface lsg)
    {
      havlak.HavlakLoopFinder_interface result;
      result = new havlak.HavlakLoopFinder(((dart._runtime.helpers.ConstructorHelper.EmptyConstructorMarker) null), type);
      result._constructor(cfg, lsg);
      return result;
    }
}