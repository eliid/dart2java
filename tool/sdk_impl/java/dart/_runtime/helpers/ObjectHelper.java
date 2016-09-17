// Copyright 2016, the Dart project authors.
// 
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// 
//     http://www.apache.org/licenses/LICENSE-2.0
// 
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package dart._runtime.helpers;

import dart._runtime.types.simple.InterfaceTypeInfo;

public class ObjectHelper {
  public static final InterfaceTypeInfo dart2java$typeInfo
      = new InterfaceTypeInfo(Object.class, null);

  public static int getHashCode(Object self) {
    // Hash code of null in Dart VM is 2011 ;)
    return self == null ? 2011 : self.hashCode();
  }

  public static boolean operatorEqual(Object self, Object other) {
    return self == null ? other == null : self.equals(other);
  }

  public static String toString(Object self) {
    return self == null ? "null" : self.toString();
  }

}
