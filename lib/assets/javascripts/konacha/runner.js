(function() {

  // adapted from https://github.com/jgonera/phantomjs-nodify
  function patchConsole() {
    var console = window.console;
    ['log', 'error', 'debug', 'warn', 'info'].forEach(function(fn) {
      var fn_ = '__orig__' + fn;
      console[fn_] = console[fn];
      console[fn] = function() {
        console[fn_](format.apply(this, arguments));
      };
    });
  }

  var formatRegExp = /%[sdj%]/g;
  function format(f) {
    var i = 1;
    var args = arguments;
    var len = args.length;
    if (len === 0) return '';
    var str = String(f).replace(formatRegExp, function(x) {
      if (i >= len) return x;
      switch (x) {
        case '%s': return String(args[i++]);
        case '%d': return Number(args[i++]);
        case '%j': return JSON.stringify(args[i++]);
        case '%%': return '%';
        default:
          return x;
      }
    });
    for (var x = args[i]; i < len; x = args[++i]) {
        str += ' ' + x;
    }
    return str;
  }

  patchConsole();


  var color = window.mocha.reporters.Base.color;

  var BaseReporter = function(runner) {
    window.mocha.reporters.Base.call(this, runner);

    runner.on('start', function() {
      Konacha.results = [];
    });

    runner.on('end', function() {
      Konacha.done = true;
    });
  };

  BaseReporter.prototype.__proto__ = window.mocha.reporters.Base.prototype;

  var DotReporter = function(runner) {
    BaseReporter.call(this, runner);

    runner.on('pass', function(test) {
      Konacha.dots += ".";
      Konacha.results.push({
        name:   test.fullTitle(),
        passed: true
      });
    });

    runner.on('fail', function(test) {
      Konacha.dots += "F";
      Konacha.results.push({
        name:    test.fullTitle(),
        passed:  false,
        message: test.err.message,
        trace:   test.err.stack
      });
    });

    runner.on('pending', function(test) {
      Konacha.dots += "P";
      Konacha.results.push({
        name:    test.fullTitle(),
        passed:  false,
        pending: true
      });
    });
  };

  DotReporter.prototype.__proto__ = BaseReporter.prototype;


  var SpecReporter = function(runner) {
    BaseReporter.call(this, runner);

    var self = this
      , indents = 0
      , n = 0;

    function indent() {
      return Array(indents).join('  ')
    }

    runner.on('suite', function(suite) {
      console.log(indent(), color('suite', suite.title));
      ++indents;
    });

    runner.on('suite end', function(suite) {
      --indents;
      if (1 == indents) console.log();
    });

    runner.on('pending', function(test) {
      console.log(indent() + color('pending', '  - ' + test.title));
    });

    runner.on('pass', function(test) {
      if ('fast' == test.speed) {
        console.log(
          indent()
            + color('checkmark', '  ✓')
            + color('pass', ' ' + test.title)
        );
      } else {
        console.log(
          indent()
            + color('checkmark', '  ✓')
            + color('pass', ' ' + test.title + ' ')
            + color(test.speed, '(' + test.duration + ')')
        )
      }
    });

    runner.on('fail', function(test, err) {
      ++n
      console.log(indent() + color('fail', '  ' + n + ') ' + test.title));
    });


    runner.on('end', function() {
      window.mocha.reporters.Base.prototype.epilogue.call(self);
    });
  };

  SpecReporter.prototype.__proto__ = BaseReporter.prototype;


  var JsonReporter = function(runner) {
    BaseReporter.call(this, runner);

    var self = this
      , currentSuite
      , parentSuite
      , suites;

    runner.on('start', function() {
      suites = []
      currentSuite = { suites: suites };
    });

    runner.on('suite', function(suite) {
      parentSuite = currentSuite;
      currentSuite = {
        title:  suite.title,
        suites: [],
        tests:  [],
        parent: parentSuite
      };
      parentSuite.suites.push(currentSuite);
    });

    runner.on('suite end', function(suite) {
      currentSuite.stats = self.stats;
      parent = currentSuite.parent;
      delete currentSuite.parent;
      currentSuite = parent;
    });

    runner.on('test end', function(test) {
      var testResult = {
        classname: test.parent.fullTitle(),
        title:     test.title,
        state:     test.state,
        duration:  test.duration
      };
      if (test.err) {
        testResult['message'] = test.err.message;
        testResult['stacktrace'] = test.err.stack;
      }
      currentSuite.tests.push(testResult);
    });

    runner.on('end', function(runner) {
      var results = suites[0].suites;
      Konacha.results = results;
    })
  };

  JsonReporter.prototype.__proto__ = BaseReporter.prototype;

  window.Konacha = {
    dots: "",

    reporters: {
      base: BaseReporter,
      json: JsonReporter,
      dot:  DotReporter,
      spec: SpecReporter
    },

    mochaOptions: {
      ui:       'bdd',
      reporter: function(runner) {
        JsonReporter(runner);
        SpecReporter(runner);
      }
    },

    getResults: function() {
      return JSON.stringify(Konacha.results);
    }
  };

})();
