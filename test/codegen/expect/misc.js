var misc;
(function(exports) {
  'use strict';
  // Function main: () → dynamic
  function main() {
    core.print(dart.toString(1));
    core.print(dart.toString(1.0));
    core.print(dart.toString(1.1));
  }
  // Exports:
  exports.main = main;
})(misc || (misc = {}));
