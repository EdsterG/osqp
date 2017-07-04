function problem = readProblem(filename, readOptions)

% readProblem : read a QP source file and apply various reformulations
% to it for testing purposes

%Configure the default settings
p = inputParser;
addParameter(p,'makeOneSided',      false);
addParameter(p,'primalPreScaling',  false);
addParameter(p,'dualPreScaling',    false);
addParameter(p,'perfectScaling',    false);
addParameter(p,'nonConvexScaling',  false);
addParameter(p,'manualScaling',     false);
addParameter(p,'primalPreScalingNorm',  2);
addParameter(p,'dualPreScalingNorm',    2);
addParameter(p,'ruizNorm',              2);

%update from external options
parse(p,readOptions);
readOptions = p.Results;

%load the QP file
load(filename);

%if a struct named problem does not exist, 
%try to make one.  Assumes variables will be in 
%MAROS format in this case
if ~exist('problem','var')
    %assume MAROS variables
    problem.A = sparse([A; speye(length(lb))]);
    problem.P = sparse(Q);
    problem.q = c;
    problem.l = [rl;lb];
    problem.u = [ru;ub];
end


if(readOptions.makeOneSided)
    problem = makeOneSided(problem);
end

if(readOptions.primalPreScaling)
    problem = primalScaling(problem,readOptions.primalPreScalingNorm);
end

if(readOptions.dualPreScaling)
    problem = dualScaling(problem,readOptions.dualPreScalingNorm);
end

if(readOptions.perfectScaling)
    problem = doPerfectScaling(problem,readOptions.ruizNorm);  
end

if(readOptions.nonConvexScaling)
   problem = doNonConvexScaling(problem,readOptions.ruizNorm);
end

if(readOptions.manualScaling)
    problem = doManualScaling(problem,readOptions.ruizNorm);
end



function problem = primalScaling(problem,scaleNorm)

s = max(1,norm(problem.q,scaleNorm));
problem.P = problem.P./s;
problem.q = problem.q./s;


function problem = dualScaling(problem, scaleNorm)

sol = osqp;
l = problem.l; 
u = problem.u;
m = min(abs(l),abs(u));
m(isinf(m)) = 0;
s = max(1,norm(m,scaleNorm));
problem.A = problem.A./s;
problem.l = problem.l./s;
problem.u = problem.u./s;




function [problem,D,E] = doManualScaling(problem, ruizNorm)

%make a solver and force it to scale the problem (scaling is the default)
% solver = osqp();
% options.verbose = 0;
% solver.setup(problem.P,problem.q,problem.A,problem.l,problem.u,options);
% work   = solver.workspace();
% 
% %get the solver scalings
% D = spdiags(work.scaling.D,0,length(work.scaling.D),length(work.scaling.D));
% E = spdiags(work.scaling.E,0,length(work.scaling.E),length(work.scaling.E));

[m,n] = deal(length(problem.l),length(problem.q));

maxIter   = 15;
scalingFlags = [ones(n+m,1)];  %scale every column

KKT = [problem.P, problem.A'; problem.A, sparse(m,m)];
S = ruizScaling(KKT,ruizNorm,maxIter,scalingFlags);

%partition scaling into D and E
D = S(1:n,1:n);
E = S(n+1:end,n+1:end);
problem = scaleProblem(problem,D,E);



function problem = makeOneSided(problem)

%rewrite the linear constraints so that they are right sided only
A = [problem.A;-problem.A];
u = [problem.u;-problem.l];

P = problem.P;
q = problem.q;

%find any rows of A/u that are unbounded on the RHS, and eliminate them
idx = isinf(u);
A(idx,:) = [];
u(idx,:) = [];

%make a fake lower bound
l = repmat(-inf,length(u),1);

%deal it all into a new problem
problem.P = P;
problem.q = q;
problem.A = A;
problem.u = u;
problem.l = l;


function problem = doPerfectScaling(problem,ruizNorm)

%rewrite the problem so that the linear cost and linear bounding
%vectors all get absorbed into the matrix problem data

%make sure it is one sided
problem = makeOneSided(problem);

%try to find some clever composite scaling
m = length(u); n = length(q);
KKT = [P q A'; q' sparse(0) u'; A u sparse(m,m)];  %not really KKT

maxIter   = 15;
scalingFlags = [ones(n,1); 0; ones(m,1)];  %don't scale the middle row
S = ruizScaling(KKT,ruizNorm,maxIter,scalingFlags);

%extract D and E
D = S(1:n,1:n); E = S(n+2:end,n+2:end);

%scale the problem
problem = scaleProblem(problem,D,E);


function problem = doNonConvexScaling(problem,ruizNorm)

%rewrite the problem so that the linear cost and linear bounding
%vectors all get absorbed into the matrix problem data

%make sure it is one sided
problem = makeOneSided(problem);

%make a nonconvex QP by adding one variable with unit cost and size
P = [problem.P problem.q; problem.q' 0];
A = [problem.A -problem.u];
q = [problem.q.*0;0];

%constraint last variable to be one
A(end+1,end) = 1;
u = [problem.u; 1];
l = [problem.l; 1];

%deal this into a new (non-convex) problem
%deal it all into a new problem
ncvxProblem.P = P;
ncvxProblem.q = q;
ncvxProblem.A = A;
ncvxProblem.u = u;
ncvxProblem.l = l;

%scale it as if it were a normal problem
[ncvxProblemScaled,D,E] = doManualScaling(ncvxProblem, ruizNorm);

%now eliminate the final variable that was making it non-convex
scaledConstant = ncvxProblemScaled.u(end);
problem.P = ncvxProblemScaled.P(1:end-1,1:end-1);
problem.A = ncvxProblemScaled.A(1:end-1,1:end-1);
problem.q = ncvxProblemScaled.q(1:end-1,:).*scaledConstant;
problem.u = ncvxProblemScaled.u(1:end-1,:).*scaledConstant;
problem.l = repmat(-inf,size(problem.u));




function problem = scaleProblem(problem,D,E)

%scale problem data using matrices D and E

problem.P = D*problem.P*D;
problem.A = E*problem.A*D;
problem.q = D*problem.q;
problem.l = E*problem.l;
problem.u = E*problem.u;


