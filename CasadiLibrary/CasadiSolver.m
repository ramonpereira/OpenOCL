classdef CasadiSolver < NLPSolver
  
  properties (Access = private)
    nlpData
    options
  end
  
  methods
    
    function self = CasadiSolver(system, phaseList, connectionList, options)
      
      constructTotalTic = tic;
      
      % create variables as casadi symbolics
      if options.nlp_casadi_mx
        vars = casadi.MX.sym('v', nlp.nv,1);
      else
        vars = casadi.SX.sym('v', nlp.nv,1);
      end
      
      xf = [];
      for k=1:length(phaseList)
        phase = phaseList{k};
        
        if k >= 2
          xf = expr('x', system.nx);
          x0 = expr('x', system.nx);
          connection_fun = connectionList{k-1};
          conection_eq = connection_fun(xf,x0);
        end
        
        x = expr('x', system.nx);
        z = expr('u', system.nz);
        u = expr('z', system.nu);
        p = expr('p', system.np);
        vi = expr('vi', integrator.ni);
        t0 = expr('t0');
        h = expr('h');
        
        % integration
        dae_expr = phase.daefun(x,z,u,p);
        dae_fun = casadi.Function('sys', {x,z,u,p}, {dae_expr});
        
        lagrangecost_expr = phase.lagrangecostfun(x,z,u,p);
        lagrangecost_fun = casadi.Function('pcost', {x,z,u,p}, {lagrangecost_expr});

        integrator_expr = phase.integratorfun(x, vi, u, t0, h, p, dae_fun, lagrangecost_fun);
        integrator_fun = casadi.Function('sys', {x,vi,u,t0,h,p}, {integrator_expr});
        
        integrator_map = integrator_fun.map(phase.N,'openmp');
        
        % cost        
        pathcost_fun = @(k,N,x,p)phase.pathcostfun(k,N,x,p);
        pathcon_fun = @(k,N,x,p)phase.pathconfun(k,N,x,p);
        
        [costs,constraints,constraints_LB,constraints_UB,~] = simultaneous( ...
            H_norm, T, ...
            xp, ni, nz, nu, np, integrator_map, ...
            pathcost_fun, pathcon_fun);
        
      end
      
      % get struct with nlp for casadi
      casadiNLP = struct;
      casadiNLP.x = vars;
      casadiNLP.f = costs;
      casadiNLP.g = constraints;
      casadiNLP.p = [];
      
      opts = self.options.nlp.casadi;
      if isfield(self.options.nlp,self.options.nlp.solver)
        opts.(self.options.nlp.solver) = self.options.nlp.(self.options.nlp.solver);
      end
      
      constructSolverTic = tic;
      casadiSolver = casadi.nlpsol('my_solver', self.options.nlp.solver,... 
                                   casadiNLP, opts);

      constructSolverTime = toc(constructSolverTic);

      nlpData = struct;
      nlpData.casadiNLP = casadiNLP;
      nlpData.constraints_LB = constraints_LB;
      nlpData.constraints_UB = constraints_UB;
      nlpData.solver = casadiSolver;
      self.timeMeasures.constructTotal = toc(constructTotalTic);
      self.timeMeasures.constructSolver = constructSolverTime;
    end
    
    function [outVars,times,objective,constraints] = solve(self,initialGuess)
      % solve(initialGuess)
      
      solveTotalTic = tic;
      
      v0 = initialGuess.value;
      
      [lbv,ubv] = self.nlp.getNlpBounds();
 
      args = struct;
      args.lbg = self.nlpData.constraints_LB;
      args.ubg = self.nlpData.constraints_UB;
      args.p = [];
      args.lbx = lbv;
      args.ubx = ubv;
      args.x0 = v0;
      
      % execute solver
      solveCasadiTic = tic;
      sol = self.nlpData.solver.call(args);
      solveCasadiTime = toc(solveCasadiTic);
      
      if strcmp(self.options.nlp.solver,'ipopt') && strcmp(self.nlpData.solver.stats().return_status,'NonIpopt_Exception_Thrown')
        oclWarning('Solver was interrupted by user.');
      end
      
      solution = sol.x.full();
      
      nlpFunEvalTic = tic;
      if nargout > 1
        [objective,constraints,~,~,times] = self.nlp.nlpFun.evaluate(solution);
      end
      nlpFunEvalTime = toc(nlpFunEvalTic);
      
      times = Variable.createNumeric(self.nlp.timesStruct,full(times));

      initialGuess.set(solution);
      outVars = initialGuess;
      
      self.timeMeasures.solveTotal      = toc(solveTotalTic);
      self.timeMeasures.solveCasadi     = solveCasadiTime;
      self.timeMeasures.nlpFunEval      = nlpFunEvalTime;
      
      oclWarningNotice()
    end
  end
  
end
