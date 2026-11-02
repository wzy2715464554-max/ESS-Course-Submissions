%% ========================================================================
%  第二周 任务四：配电网储能选址定容优化（Big-M 线性化 + LinDistFlow）
%                与交流潮流闭环验证，含规划参数灵敏度分析
%  姓名：刘宇成      学号：208231323      班级：储能231
%  算例：case_nongcun（49 节点农村配电网），alpha = 1.046
%  候选节点：{4, 9, 14}（模型 A），离散档位 1~5 MW / 1~5 MWh
%  交付：Fig_Week2_208231323.png / .pdf / .fig、result_summary.mat
%% ========================================================================
clear; clc; close all;
yalmip('clear');

%% 0. 课程资源路径（换电脑时只需修改这一行）
mat_dir = "C:\Users\Administrator\Desktop\matlab\ESS-Course-Materials-main\ESS-Course-Materials-main";
if ~isfolder(mat_dir)
    mat_dir = uigetdir(pwd, '请选择本机 ESS-Course-Materials 仓库根目录');
end
addpath(fullfile(mat_dir, 'cases'));
out_dir = fileparts(mfilename('fullpath'));
if isempty(out_dir)
    out_dir = pwd;
end

%% 1. 学号映射
Stu_ID  = 208231323;
XY      = mod(Stu_ID, 100);
X_digit = floor(XY / 10);
Y_digit = mod(XY, 10);
alpha   = 1 + 0.002 * XY;

if ismember(Y_digit, [0, 1, 2, 3])
    case_name = 'case_nongcun';
elseif ismember(Y_digit, [4, 5, 6])
    case_name = 'case_chengshi_A';
else
    case_name = 'case_kaifaqu_A';
end

if ismember(X_digit, [0, 1, 2])
    cand_buses = [4, 9, 14];
elseif ismember(X_digit, [3, 4, 5])
    cand_buses = [5, 11, 16];
else
    cand_buses = [6, 13, 17];
end

%% 2. 基准参数
par_base = struct();
par_base.mat_dir    = mat_dir;
par_base.case_name  = case_name;
par_base.alpha      = alpha;
par_base.cand_buses = cand_buses;
par_base.c_P        = 0.08 * 1e6;   % 元/MW
par_base.c_E        = 0.55 * 1e6;   % 元/MWh
par_base.c_om       = 200 * 1e3;    % 元/(MW·年)
par_base.Y_life     = 20;
par_base.d_rate     = 0.05;
par_base.D_days     = 365;
par_base.V_min_Lin  = 0.960;
par_base.V_max_Lin  = 1.050;
par_base.P_opt_MW   = [1, 2, 3, 4, 5];
par_base.E_opt_MWh  = [1, 2, 3, 4, 5];
par_base.eta_ch     = 0.90;
par_base.eta_dis    = 0.95;
par_base.SoC_min    = 0.20;
par_base.SoC_max    = 0.80;
par_base.SoC_0      = 0.50;

%% 3. 基准场景求解
fprintf('=== 基准场景：c_E = %.0f 万元/MWh，V_min,Lin = %.3f p.u. ===\n', ...
    par_base.c_E / 1e4, par_base.V_min_Lin);
R0 = local_planning(par_base, true);

fprintf('\n================ 第二周：储能选址定容与交流潮流验证 ================\n');
fprintf('学号: %d | 算例: %s | 求解器: intlinprog | 用时 %.1f s\n', Stu_ID, case_name, R0.solve_seconds);
for idx = 1:numel(cand_buses)
    fprintf('候选节点 %2d: z=%d | 额定功率 = %d MW | 额定容量 = %d MWh\n', ...
        cand_buses(idx), R0.z(idx), R0.P_rated(idx), R0.E_rated(idx));
end
fprintf('年化投资 %.2f 万元 | 年运维 %.2f 万元 | 年购电 %.2f 万元 | 年综合费用 %.2f 万元\n', ...
    R0.C_inv / 1e4, R0.C_om / 1e4, R0.C_grid / 1e4, R0.Obj / 1e4);
fprintf('事后核算年降损收益 %.2f 万元\n', R0.B_loss / 1e4);
fprintf('LinDistFlow 最低电压 %.4f p.u. | 交流潮流最低电压 %.4f p.u. | 最大偏差 %.4f p.u.\n', ...
    R0.V_lin_min, R0.V_ac_min, R0.Max_V_Err);
fprintf('===================================================================\n');

%% 4. 灵敏度分析
c_E_list = [15, 25, 35, 55, 75, 100] * 1e4;
sens_cE = struct('c_E', num2cell(c_E_list), 'P_total', 0, 'E_total', 0, ...
    'Obj', 0, 'Sites', 0, 'P_rated', [], 'E_rated', []);
for k = 1:numel(c_E_list)
    pk = par_base; pk.c_E = c_E_list(k);
    Rk = local_planning(pk, true);
    sens_cE(k).P_total = sum(Rk.P_rated);
    sens_cE(k).E_total = sum(Rk.E_rated);
    sens_cE(k).Obj     = Rk.Obj;
    sens_cE(k).Sites   = find(Rk.z == 1);
    sens_cE(k).P_rated = Rk.P_rated;
    sens_cE(k).E_rated = Rk.E_rated;
    fprintf('[c_E] %2.0f 万元/MWh -> 站点 %s，%d MW / %d MWh，年费用 %.2f 万元\n', ...
        c_E_list(k)/1e4, mat2str(find(Rk.z==1)'), sum(Rk.P_rated), sum(Rk.E_rated), Rk.Obj/1e4);
end

V_list = [0.955, 0.960, 0.965, 0.970];
sens_V = struct('V_min', num2cell(V_list), 'P_total', 0, 'E_total', 0, ...
    'Obj', 0, 'Sites', 0, 'Max_V_Err', 0, 'V_ac_min', 0);
for k = 1:numel(V_list)
    pk = par_base; pk.V_min_Lin = V_list(k);
    Rk = local_planning(pk, true);
    if Rk.infeasible
        sens_V(k).P_total = NaN; sens_V(k).E_total = NaN;
        sens_V(k).Obj = NaN; sens_V(k).V_ac_min = NaN;
    else
        sens_V(k).P_total   = sum(Rk.P_rated);
        sens_V(k).E_total   = sum(Rk.E_rated);
        sens_V(k).Obj       = Rk.Obj;
        sens_V(k).V_ac_min  = Rk.V_ac_min;
    end
    sens_V(k).Sites     = find(Rk.z == 1);
    sens_V(k).Max_V_Err = Rk.Max_V_Err;
    fprintf('[Vmin] %.3f p.u. -> 站点 %s，%d MW / %d MWh，年费用 %.2f 万元，AC 最低 %.4f p.u.\n', ...
        V_list(k), mat2str(find(Rk.z==1)'), sum(Rk.P_rated), sum(Rk.E_rated), Rk.Obj/1e4, Rk.V_ac_min);
end

%% 5. 标准化输出结构体
res_file = fullfile(out_dir, 'result_summary.mat');
if isfile(res_file)
    S0 = load(res_file);
    if isfield(S0, 'Result'), Result = S0.Result; else, Result = struct(); end
else
    Result = struct();
end

Result.StuID       = Stu_ID;
Result.Obj_Value   = R0.Obj;
Result.Opt_Sites   = find(R0.z == 1);
Result.Opt_P_rated = R0.P_rated;
Result.Opt_E_rated = R0.E_rated;
Result.Max_V_Err   = R0.Max_V_Err;

Result.Task4 = struct( ...
    'case_name', case_name, 'alpha', alpha, 'cand_buses', cand_buses, ...
    'c_P', par_base.c_P, 'c_E', par_base.c_E, 'c_om', par_base.c_om, ...
    'CRF', R0.CRF, 'D_days', par_base.D_days, 'V_min_Lin', par_base.V_min_Lin, ...
    'C_inv', R0.C_inv, 'C_om', R0.C_om, 'C_grid', R0.C_grid, ...
    'B_loss_ann', R0.B_loss, 'V_lin_min', R0.V_lin_min, 'V_ac_min', R0.V_ac_min, ...
    'Max_V_Err', R0.Max_V_Err, 'Solve_Seconds', R0.solve_seconds, ...
    'P_net_MW', R0.P_net, 'V_ac_base', R0.V_base, 'V_ac_ess', R0.V_ess, 'V_lin', R0.V_lin, ...
    'Sens_cE', sens_cE, 'Sens_Vmin', sens_V );

save(res_file, 'Result');
fprintf('[OK] 结果已保存：%s\n', res_file);

%% 6. 绘图
[~, worst_bus] = min(min(R0.V_base, [], 2));
T = size(R0.V_base, 2);

fig1 = figure('Name', '任务四：选址定容结果与灵敏度', 'Color', 'w', 'Position', [120, 80, 860, 900]);
if isprop(fig1, 'Theme'), theme(fig1, 'light'); end

subplot(3, 1, 1);
p1 = plot(1:T, R0.V_base(worst_bus, :), '--k', 'LineWidth', 1.5); hold on;
p2 = plot(1:T, R0.V_lin(worst_bus, :), '-^', 'LineWidth', 1.5, 'MarkerSize', 5, ...
    'Color', [0.00, 0.45, 0.74], 'MarkerFaceColor', [0.00, 0.45, 0.74]);
p3 = plot(1:T, R0.V_ess(worst_bus, :), '-o', 'LineWidth', 1.7, 'MarkerSize', 5, ...
    'Color', [0.85, 0.20, 0.15], 'MarkerFaceColor', [0.85, 0.20, 0.15]);
yline(0.95, ':r', 'LineWidth', 1.4);
xlim([1, T]); xticks(0:4:24);
ylim([min([R0.V_base(worst_bus,:), R0.V_ess(worst_bus,:), 0.948]) - 0.004, ...
      max([R0.V_lin(worst_bus,:), R0.V_ess(worst_bus,:), 0.980]) + 0.020]);
set(gca, 'Color', 'w', 'XColor', 'k', 'YColor', 'k', 'FontName', 'Times New Roman', ...
    'FontSize', 10.5, 'Box', 'on', 'TickDir', 'in', 'GridLineStyle', '--', 'GridAlpha', 0.3);
xlabel('\fontname{宋体}时间 \fontname{Times New Roman}{\itt}\rm{/h}', 'FontSize', 11, 'Interpreter', 'tex');
ylabel('\fontname{宋体}节点电压 \fontname{Times New Roman}{\itV}\rm{/(p.u.)}', 'FontSize', 11, 'Interpreter', 'tex');
title(sprintf('\\fontname{宋体}(a) 薄弱节点 \\fontname{Times New Roman}%d \\fontname{宋体}的 24 h 电压对比 (\\Delta{\\itV}_{\\rm{max}} = %.4f p.u.)', ...
    worst_bus, R0.Max_V_Err), 'FontSize', 11, 'FontWeight', 'normal', 'Interpreter', 'tex');
legend([p1, p2, p3], {'规划前 AC 潮流', '规划后 LinDistFlow', '规划后 AC 潮流'}, ...
    'Location', 'north', 'NumColumns', 3, 'FontSize', 9);
grid on;

subplot(3, 1, 2);
yyaxis left
bar(1:numel(sens_cE), cellfun(@(x) x, {sens_cE.E_total}), 0.55, ...
    'FaceColor', [0.20, 0.45, 0.70], 'EdgeColor', 'none');
ylabel('总配置容量 / MWh', 'FontSize', 10.5);
yyaxis right
plot(1:numel(sens_cE), cellfun(@(x) x, {sens_cE.Obj}) / 1e4, '-o', 'Color', [0.85, 0.35, 0.15], ...
    'LineWidth', 1.6, 'MarkerFaceColor', [0.85, 0.35, 0.15]);
ylabel('年综合费用 / 万元', 'FontSize', 10.5);
set(gca, 'XColor', 'k', 'YColor', 'k', 'Box', 'on', 'TickDir', 'in');
xticks(1:numel(sens_cE));
xticklabels(arrayfun(@(x) sprintf('%d', x/1e4), c_E_list, 'UniformOutput', false));
xlabel('单位能量投资成本 {\itc}_E / (万元·MWh^{-1})', 'FontSize', 10.5);
title('(b) 容量与年费用随 {\itc}_E 的变化', 'FontSize', 11, 'FontWeight', 'normal');
grid on;

subplot(3, 1, 3);
E_tot = cellfun(@(x) x, {sens_V.E_total});
P_tot = cellfun(@(x) x, {sens_V.P_total});
bar(1:numel(sens_V), E_tot, 0.5, 'FaceColor', [0.47, 0.67, 0.19], 'EdgeColor', 'none');
hold on;
plot(1:numel(sens_V), P_tot, '-s', 'Color', [0.85, 0.20, 0.15], ...
    'LineWidth', 1.6, 'MarkerFaceColor', [0.85, 0.20, 0.15]);
for k = 1:numel(sens_V)
    if isnan(E_tot(k))
        text(k, 0.12, '不可行', 'HorizontalAlignment', 'center', 'FontSize', 9, 'Color', [0.6, 0.1, 0.1]);
    end
end
set(gca, 'XColor', 'k', 'YColor', 'k', 'Box', 'on', 'TickDir', 'in');
xticks(1:numel(sens_V));
xticklabels(arrayfun(@(x) sprintf('%.3f', x), V_list, 'UniformOutput', false));
xlabel('电压下限 {\itV}_{min,Lin} / p.u.', 'FontSize', 10.5);
ylabel('总配置容量 / (MW 或 MWh)', 'FontSize', 10.5);
legend({'总能量容量 E', '总功率容量 P'}, 'Location', 'northwest', 'FontSize', 9);
title('(c) 容量随电压下限的变化', 'FontSize', 11, 'FontWeight', 'normal');
grid on;

exportgraphics(fig1, fullfile(out_dir, sprintf('Fig_Week2_%d.png', Stu_ID)), ...
    'Resolution', 600, 'BackgroundColor', 'white');
exportgraphics(fig1, fullfile(out_dir, sprintf('Fig_Week2_%d.pdf', Stu_ID)), ...
    'ContentType', 'vector', 'BackgroundColor', 'white');
savefig(fig1, fullfile(out_dir, sprintf('Fig_Week2_%d.fig', Stu_ID)));

%% ======================= 局部函数 =======================
function R = local_planning(p, quiet)
if nargin < 2, quiet = false; end

profiles = load(fullfile(p.mat_dir, 'cases', 'profiles_24h.mat'));
T = profiles.T;
load_curve_pu = profiles.load_curve_pu;
price_MWh     = profiles.price_MWh(:);

mpc = loadcase(p.case_name);
Sbase = mpc.baseMVA;
N_bus = size(mpc.bus, 1);
N_br  = size(mpc.branch, 1);
fbus  = mpc.branch(:, 1);
tbus  = mpc.branch(:, 2);
r_br  = mpc.branch(:, 3);
x_br  = mpc.branch(:, 4);

Pd_pu = (mpc.bus(:, 3) * p.alpha / Sbase) * load_curve_pu';
Qd_pu = (mpc.bus(:, 4) * p.alpha / Sbase) * load_curve_pu';

cand_buses = p.cand_buses;
N_cand = numel(cand_buses);
P_opt_MW  = p.P_opt_MW;
E_opt_MWh = p.E_opt_MWh;
K = numel(E_opt_MWh);

CRF = (p.d_rate * (1 + p.d_rate)^p.Y_life) / ((1 + p.d_rate)^p.Y_life - 1);

z        = binvar(N_cand, 1, 'full');
w        = binvar(N_cand, K, 'full');
SoC      = sdpvar(N_cand, T, 'full');
delta    = sdpvar(N_cand, K, T, 'full');
P_ch_MW  = sdpvar(N_cand, T, 'full');
P_dis_MW = sdpvar(N_cand, T, 'full');
u_ch     = binvar(N_cand, T, 'full');
U_lin     = sdpvar(N_bus, T, 'full');
P_br      = sdpvar(N_br,  T, 'full');
Q_br      = sdpvar(N_br,  T, 'full');
P_grid_pu = sdpvar(1,     T, 'full');
Q_grid_pu = sdpvar(1,     T, 'full');

Constraints = [];
P_rated = w * P_opt_MW';
E_rated = w * E_opt_MWh';
P_max_bound = max(P_opt_MW);

for idx = 1:N_cand
    Constraints = [Constraints, sum(w(idx, :)) == z(idx)];
    Constraints = [Constraints, p.SoC_min <= SoC(idx, :) <= p.SoC_max];
    Constraints = [Constraints, SoC(idx, T) == p.SoC_0];
    Constraints = [Constraints, 0 <= P_ch_MW(idx, :)  <= P_rated(idx)];
    Constraints = [Constraints, 0 <= P_dis_MW(idx, :) <= P_rated(idx)];
    Constraints = [Constraints, P_ch_MW(idx, :)  <= u_ch(idx, :) * P_max_bound];
    Constraints = [Constraints, P_dis_MW(idx, :) <= (1 - u_ch(idx, :)) * P_max_bound];

    for k = 1:K
        d_vec = reshape(delta(idx, k, :), 1, T);
        Constraints = [Constraints, p.SoC_min * w(idx, k) <= d_vec <= p.SoC_max * w(idx, k)];
        Constraints = [Constraints, SoC(idx, :) - p.SoC_max * (1 - w(idx, k)) <= d_vec <= ...
            SoC(idx, :) - p.SoC_min * (1 - w(idx, k))];
    end

    for t = 1:T
        if t == 1
            E_prev = E_opt_MWh * (p.SoC_0 * w(idx, :))';
        else
            E_prev = E_opt_MWh * reshape(delta(idx, :, t - 1), K, 1);
        end
        E_curr = E_opt_MWh * reshape(delta(idx, :, t), K, 1);
        Constraints = [Constraints, E_curr - E_prev == ...
            p.eta_ch * P_ch_MW(idx, t) - P_dis_MW(idx, t) / p.eta_dis];
    end
end

A_from  = sparse(fbus, 1:N_br, 1, N_bus, N_br);
A_to    = sparse(tbus, 1:N_br, 1, N_bus, N_br);
A_cand  = sparse(cand_buses, 1:N_cand, 1, N_bus, N_cand);
A_slack = sparse(1, 1, 1, N_bus, 1);

Constraints = [Constraints, A_to * P_br - A_from * P_br + A_slack * P_grid_pu + ...
    A_cand * ((P_dis_MW - P_ch_MW) / Sbase) == Pd_pu];
Constraints = [Constraints, A_to * Q_br - A_from * Q_br + A_slack * Q_grid_pu == Qd_pu];
Constraints = [Constraints, U_lin(1, :) == 1.0];
Constraints = [Constraints, (p.V_min_Lin^2) <= U_lin(2:end, :) <= (p.V_max_Lin^2)];

for b = 1:N_br
    Constraints = [Constraints, U_lin(tbus(b), :) == U_lin(fbus(b), :) - ...
        2 * (r_br(b) * P_br(b, :) + x_br(b) * Q_br(b, :))];
end

C_inv_ann  = CRF * sum(p.c_P * P_rated + p.c_E * E_rated);
C_om_ann   = sum(p.c_om * P_rated);
C_grid_ann = p.D_days * sum((Sbase * P_grid_pu') .* price_MWh);
Objective  = C_inv_ann + C_om_ann + C_grid_ann;

native_dir = fullfile(matlabroot, 'toolbox', 'optim', 'optim');
if exist(native_dir, 'dir'), addpath(native_dir, '-begin'); end
ops = sdpsettings('solver', 'intlinprog', 'verbose', 0);
ops.intlinprog.RelativeGapTolerance = 1e-6;
ops.intlinprog.AbsoluteGapTolerance = 1e-8;

t0 = tic;
sol = optimize(Constraints, Objective, ops);
R.solve_seconds = toc(t0);

if sol.problem ~= 0
    % 该参数组合下可行域为空（例如电压下限过严、离散档位不足以支撑）
    R.infeasible = true;
    R.Obj = NaN; R.C_inv = NaN; R.C_om = NaN; R.C_grid = NaN; R.CRF = CRF;
    R.B_loss = NaN;
    R.z = zeros(N_cand, 1); R.P_rated = zeros(N_cand, 1); R.E_rated = zeros(N_cand, 1);
    R.V_lin = nan(N_bus, T); R.V_base = nan(N_bus, T); R.V_ess = nan(N_bus, T);
    R.P_net = nan(N_cand, T);
    R.V_lin_min = NaN; R.V_ac_min = NaN; R.Max_V_Err = NaN;
    if ~quiet
        fprintf('  该参数组合不可行：%s\n', yalmiperror(sol.problem));
    end
    return;
end
R.infeasible = false;

V_lin = sqrt(value(U_lin));
P_net = value(P_dis_MW - P_ch_MW);
V_base = zeros(N_bus, T); V_ess = zeros(N_bus, T);
Ploss_b = zeros(T, 1);    Ploss_e = zeros(T, 1);
mpopt = mpoption('verbose', 0, 'out.all', 0);
for t = 1:T
    mpc_b = mpc;
    mpc_b.bus(:, 3) = Pd_pu(:, t) * Sbase;
    mpc_b.bus(:, 4) = Qd_pu(:, t) * Sbase;
    res_b = runpf(mpc_b, mpopt);
    V_base(:, t) = res_b.bus(:, 8);
    Ploss_b(t)   = sum(real(get_losses(res_b)));

    mpc_e = mpc_b;
    mpc_e.bus(cand_buses, 3) = mpc_e.bus(cand_buses, 3) - P_net(:, t);
    res_e = runpf(mpc_e, mpopt);
    V_ess(:, t) = res_e.bus(:, 8);
    Ploss_e(t)  = sum(real(get_losses(res_e)));
end

R.Obj        = value(Objective);
R.C_inv      = value(C_inv_ann);
R.C_om       = value(C_om_ann);
R.C_grid     = value(C_grid_ann);
R.CRF        = CRF;
R.B_loss     = p.D_days * sum((Ploss_b - Ploss_e) .* price_MWh);
R.z          = round(value(z));
R.P_rated    = round(value(P_rated));
R.E_rated    = round(value(E_rated));
R.V_lin      = V_lin;
R.V_base     = V_base;
R.V_ess      = V_ess;
R.P_net      = P_net;
R.V_lin_min  = min(V_lin(:));
R.V_ac_min   = min(V_ess(:));
R.Max_V_Err  = max(max(abs(V_lin - V_ess)));

if ~quiet
    fprintf('  求解用时 %.1f s\n', R.solve_seconds);
end
end
