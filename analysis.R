# Birth centers and certificate of need, 2007 to 2024
# Reads data/panel_state_year.csv, data/panel_state_month.csv, data/con_birth_centers.csv
# Writes output/*.csv, output/readme_tables.md, output/headline_numbers.txt, figures/*.png
#
# Run from the repository root: Rscript analysis.R

need <- c("tidyverse", "scales", "fixest", "ggrepel")
for (p in need) if (!requireNamespace(p, quietly = TRUE)) install.packages(p, repos = "https://cloud.r-project.org")
suppressPackageStartupMessages({ library(tidyverse); library(scales); library(fixest); library(ggrepel) })
dir.create("output", showWarnings = FALSE); dir.create("figures", showWarnings = FALSE)

panel <- read_csv("data/panel_state_year.csv", show_col_types = FALSE)
con   <- read_csv("data/con_birth_centers.csv", show_col_types = FALSE)
monthly <- read_csv("data/panel_state_month.csv", show_col_types = FALSE)

# CON status groups: states that never covered birth centers, states that still do, and the
# six that dropped the requirement between 2023 and 2025.
panel <- panel %>%
  mutate(con_group = case_when(con_ever == 0 ~ "Never required CON",
                               con_repealed == 1 ~ "Dropped CON 2023 to 2025",
                               TRUE ~ "Still requires CON"),
         con_group = factor(con_group, c("Never required CON", "Dropped CON 2023 to 2025", "Still requires CON")))
births <- panel %>% filter(year <= 2024)
pal <- c("Never required CON" = "#1b7837", "Dropped CON 2023 to 2025" = "#e08214", "Still requires CON" = "#762a83")
theme_set(theme_minimal(base_size = 12) + theme(panel.grid.minor = element_blank(), plot.title.position = "plot"))

# ---- 1. National trend --------------------------------------------------------
national <- births %>% group_by(year) %>%
  summarise(births = sum(births), fbc_births = sum(fbc_births, na.rm = TRUE), home_births = sum(home_births, na.rm = TRUE),
            states_suppressed = sum(fbc_suppressed), .groups = "drop") %>%
  mutate(fbc_per_1000 = fbc_births / births * 1000, home_per_1000 = home_births / births * 1000)
write_csv(national, "output/national_trend.csv")

p1 <- national %>% select(year, `Freestanding birth center` = fbc_per_1000, `Home` = home_per_1000) %>%
  pivot_longer(-year, names_to = "place", values_to = "rate") %>%
  ggplot(aes(year, rate, color = place)) +
  geom_line(linewidth = 1.1) + geom_point(size = 2) +
  scale_color_manual(values = c("Freestanding birth center" = "#2166ac", "Home" = "#b2182b"), name = NULL) +
  scale_x_continuous(breaks = seq(2007, 2024, 2)) +
  labs(title = "Births outside hospitals per 1,000 US births, 2007 to 2024",
       subtitle = "Freestanding birth center births rose from 2.5 to 6.5 per 1,000 by 2022, then slipped. Home births jumped in 2020 and stayed up.",
       x = NULL, y = "Births per 1,000 live births", caption = "NCHS natality data via CDC WONDER, by state of residence.") +
  theme(legend.position = "top")
ggsave("figures/fig1_national_trend.png", p1, width = 9, height = 5.5, dpi = 150, bg = "white")

# ---- 2. 2024 state ranking by CON status --------------------------------------
# CON status is as of 2022, before the recent repeals, so the comparison is between the
# regimes states actually lived under while these birth centers were being built.
state24 <- births %>% filter(year == 2024) %>%
  select(state, state_name, births, fbc_births, fbc_suppressed, fbc_per_1000_births, home_per_1000_births,
         npi_active_stock, npi_stock_per_100k_births, con_group, con_ever, con_repealed, repeal_effective) %>%
  arrange(desc(fbc_per_1000_births))
write_csv(state24, "output/state_table_2024.csv")

p2 <- state24 %>%
  mutate(rate = ifelse(fbc_suppressed == 1, 0, fbc_per_1000_births),
         lab = ifelse(fbc_suppressed == 1, "fewer than 10 births", ""),
         state_name = fct_reorder(state_name, rate)) %>%
  ggplot(aes(rate, state_name, fill = con_group)) +
  geom_col(width = 0.75) +
  geom_text(aes(label = lab), hjust = -0.1, size = 2.8, color = "grey40") +
  scale_fill_manual(values = pal, name = "Certificate of need for birth centers (status as of 2022)") +
  scale_x_continuous(expand = expansion(mult = c(0, 0.08))) +
  labs(title = "Freestanding birth center births per 1,000 births by state of residence, 2024",
       subtitle = "Most states that required a certificate of need sit near the bottom. Alaska and Delaware are the exceptions.",
       x = "Birth center births per 1,000 live births", y = NULL,
       caption = "NCHS natality via CDC WONDER (counts under 10 withheld). CON status: Pacific Legal Foundation and NCSL, 2025.") +
  theme(legend.position = "top", legend.direction = "vertical", axis.text.y = element_text(size = 8), plot.caption = element_text(size = 8))
ggsave("figures/fig2_state_ranking_2024.png", p2, width = 9, height = 11, dpi = 150, bg = "white")

# ---- 3. Trend by CON group -----------------------------------------------------
grp <- births %>% filter(!is.na(fbc_per_1000_births)) %>%
  group_by(con_group, year) %>%
  summarise(median_rate = median(fbc_per_1000_births), n = n(),
            pooled_rate = sum(fbc_births) / sum(births) * 1000, .groups = "drop")
write_csv(grp, "output/trend_by_con_group.csv")
p3 <- ggplot(grp, aes(year, median_rate, color = con_group)) +
  geom_line(linewidth = 1.1) + geom_point(size = 2) +
  scale_color_manual(values = pal, name = NULL) +
  scale_x_continuous(breaks = seq(2007, 2024, 2)) +
  labs(title = "Median state rate of birth center births, by certificate of need regime",
       subtitle = "States that never required a CON for birth centers pulled away after 2012.\nThe six states that dropped CON in 2023 to 2025 were the lowest group throughout.",
       x = NULL, y = "Median birth center births per 1,000 (states with 10 or more)", caption = "NCHS natality via CDC WONDER.") +
  theme(legend.position = "top")
ggsave("figures/fig3_trend_by_con_group.png", p3, width = 9, height = 5.5, dpi = 150, bg = "white")

# ---- 4. The six repeal states -------------------------------------------------
repealers <- con %>% filter(!is.na(repeal_effective)) %>% select(state, state_name, repeal_effective, repeal_law)
never_med <- births %>% filter(con_ever == 0, !is.na(fbc_per_1000_births)) %>% group_by(year) %>%
  summarise(never_median = median(fbc_per_1000_births), .groups = "drop")
rep_panel <- births %>% filter(state %in% repealers$state) %>%
  select(state, state_name, year, fbc_births, fbc_suppressed, fbc_per_1000_births, npi_entries, repeal_effective) %>%
  left_join(never_med, by = "year")
write_csv(rep_panel, "output/repeal_states_panel.csv")
p4 <- rep_panel %>% mutate(rate = ifelse(fbc_suppressed == 1, NA, fbc_per_1000_births),
                           repeal_year = as.numeric(substr(repeal_effective, 1, 4)) + (as.numeric(substr(repeal_effective, 6, 7)) - 1) / 12,
                           panel_lab = paste0(state_name, " (CON dropped ", repeal_effective, ")")) %>%
  ggplot(aes(year)) +
  geom_line(aes(y = never_median), color = "grey65", linewidth = 0.9, linetype = "22") +
  geom_line(aes(y = rate), color = "#e08214", linewidth = 1.1) + geom_point(aes(y = rate), color = "#e08214", size = 1.8) +
  geom_vline(aes(xintercept = repeal_year), color = "black", linewidth = 0.5) +
  facet_wrap(~ panel_lab, ncol = 3, scales = "free_y") +
  scale_x_continuous(breaks = seq(2008, 2024, 4)) +
  labs(title = "Birth center births per 1,000 in the six states that dropped CON for birth centers",
       subtitle = "Orange: the state. Dashed grey: median of states that never required a CON. Black line: repeal took effect. Births data end in 2024.",
       x = NULL, y = "Birth center births per 1,000 live births", caption = "NCHS natality via CDC WONDER, by state of residence. Gaps are years with fewer than 10 birth center births.")
ggsave("figures/fig4_repeal_states.png", p4, width = 11, height = 6.5, dpi = 150, bg = "white")

# ---- 5. NPPES entries: the supply side -----------------------------------------
npi_nat <- panel %>% filter(year >= 2010) %>% group_by(year, partial_year) %>%
  summarise(entries = sum(npi_entries), entries_annualized = sum(npi_entries_annualized), .groups = "drop")
write_csv(npi_nat, "output/npi_entries_national.csv")
rep_npi <- panel %>% filter(state %in% repealers$state, year >= 2015) %>%
  select(state, state_name, year, npi_entries, event_time, repeal_effective)
ctrl_npi <- panel %>% filter(con_ever == 0, year >= 2015) %>% group_by(year) %>%
  summarise(never_mean_entries_per_100k = mean(npi_entries_per_100k_births), .groups = "drop")
write_csv(rep_npi, "output/repeal_states_npi_entries.csv")
p5 <- panel %>% filter(state %in% repealers$state, year >= 2015) %>%
  mutate(panel_lab = paste0(state_name, " (", repeal_effective, ")"),
         repeal_year = as.numeric(substr(repeal_effective, 1, 4)) + (as.numeric(substr(repeal_effective, 6, 7)) - 1) / 12) %>%
  ggplot(aes(year, npi_entries)) +
  geom_col(aes(fill = partial_year == 1), width = 0.8) +
  geom_vline(aes(xintercept = repeal_year), color = "black", linewidth = 0.5) +
  scale_fill_manual(values = c(`FALSE` = "#e08214", `TRUE` = "#fdd49e"), labels = c("Full year", "2026 through October 20"), name = NULL) +
  facet_wrap(~ panel_lab, ncol = 3) +
  scale_x_continuous(breaks = seq(2015, 2026, 2)) +
  labs(title = "New birth center NPIs registered per year in the six repeal states, 2015 to 2026",
       subtitle = "Organizations in NPPES with Clinic/Center, Birthing as primary taxonomy. Black line: CON dropped. Little has followed the repeals so far.",
       x = NULL, y = "New NPIs", caption = "NPPES NPI Registry, pulled October 20, 2026. Active NPIs only; closed centers that deactivated are not counted.") +
  theme(legend.position = "top")
ggsave("figures/fig5_repeal_states_npi_entries.png", p5, width = 11, height = 6.5, dpi = 150, bg = "white")

# ---- 6. Map --------------------------------------------------------------------
map_ok <- tryCatch({
  library(usmap)
  md <- state24 %>% mutate(rate = ifelse(fbc_suppressed == 1, NA, fbc_per_1000_births))
  p6 <- plot_usmap(data = md, values = "rate", regions = "states", color = "white") +
    scale_fill_viridis_c(name = "Birth center births\nper 1,000 (2024)", option = "mako", direction = -1, na.value = "grey85", trans = "sqrt") +
    labs(title = "Freestanding birth center births per 1,000 births by state of residence, 2024",
         subtitle = "Grey: fewer than 10 birth center births (Arkansas, Hawaii, Mississippi, North Dakota, Rhode Island).",
         caption = "NCHS natality via CDC WONDER.") +
    theme(legend.position = "right")
  ggsave("figures/fig6_map_2024.png", p6, width = 10, height = 6.5, dpi = 150, bg = "white"); TRUE
}, error = function(e) { message("map skipped: ", conditionMessage(e)); FALSE })

# ---- 7. Models ---------------------------------------------------------------
# (a) Cross-section, 2022: how different are CON and non-CON states?
cs <- births %>% filter(year == 2022, !is.na(fbc_per_1000_births) | fbc_suppressed == 1) %>%
  mutate(rate = ifelse(fbc_suppressed == 1, 0, fbc_per_1000_births))   # suppressed states counted at zero (they are under 10 births)
wt <- wilcox.test(rate ~ con_ever, data = cs, exact = FALSE)
cs_sum <- cs %>% group_by(con_ever) %>%
  summarise(n = n(), median = median(rate), mean = mean(rate), share_under_1_per_1000 = mean(rate < 1), .groups = "drop") %>%
  mutate(group = ifelse(con_ever == 1, "CON required (2022)", "No CON (2022)"), wilcoxon_p = wt$p.value)
write_csv(cs_sum, "output/con_comparison_2022.csv")

# (b) Panel: two-way fixed effects on the share of the year a CON requirement was in force.
# The switchers inside the births window are West Virginia (mid 2023), Connecticut (2024), and Georgia (mid 2024);
# the other three repeals took effect after the last year of births data, so the estimate rests on very little.
mod_dat <- births %>% filter(!is.na(fbc_per_1000_births) | fbc_suppressed == 1) %>%
  mutate(rate = ifelse(fbc_suppressed == 1, 0, fbc_per_1000_births), log_rate = log1p(rate),
         npi_rate = npi_entries_per_100k_births)
twfe_rate <- feols(rate ~ con_share_of_year | state + year, data = mod_dat, cluster = ~state)
twfe_log  <- feols(log_rate ~ con_share_of_year | state + year, data = mod_dat, cluster = ~state)
# (c) Panel on the supply margin, NPI entries per 100k births, 2010 to 2025, which reaches past all six repeals.
npi_dat <- panel %>% filter(year >= 2010, year <= 2025)
twfe_npi <- feols(npi_entries_per_100k_births ~ con_share_of_year | state + year, data = npi_dat, cluster = ~state)
# Event study on NPI entries with Sun and Abraham cohort weights; cohort = repeal year, never-treated = states without CON ever plus still-CON states
npi_dat <- npi_dat %>% mutate(cohort = ifelse(con_repealed == 1, as.numeric(substr(repeal_effective, 1, 4)), 10000))
es <- tryCatch(feols(npi_entries_per_100k_births ~ sunab(cohort, year) | state + year, data = npi_dat, cluster = ~state), error = function(e) NULL)
tidy_fe <- function(m, label) {
  ct <- coeftable(m); tibble(model = label, term = rownames(ct), estimate = ct[, 1], se = ct[, 2], p = ct[, 4],
                             n = nobs(m), states = length(unique(m$fixef_id$state)))
}
models <- bind_rows(tidy_fe(twfe_rate, "FBC births per 1,000 (2007 to 2024)"),
                    tidy_fe(twfe_log, "log(1 + FBC births per 1,000) (2007 to 2024)"),
                    tidy_fe(twfe_npi, "New birth center NPIs per 100k births (2010 to 2025)"))
write_csv(models, "output/twfe_models.csv")
if (!is.null(es)) {
  esd <- as.data.frame(coeftable(es)) %>% rownames_to_column("term") %>%
    transmute(event_time = as.numeric(str_extract(term, "-?\\d+")), estimate = Estimate, se = `Std. Error`)
  write_csv(esd, "output/event_study_npi_entries.csv")
  p7 <- ggplot(esd %>% filter(event_time >= -8), aes(event_time, estimate)) +
    geom_hline(yintercept = 0, color = "grey50") + geom_vline(xintercept = -0.5, linetype = "22", color = "grey50") +
    geom_errorbar(aes(ymin = estimate - 1.96 * se, ymax = estimate + 1.96 * se), width = 0.2, color = "#e08214") +
    geom_point(size = 2.5, color = "#e08214") +
    labs(title = "Event study: new birth center NPIs per 100,000 births around a CON repeal",
         subtitle = "Sun and Abraham estimator, six repeal cohorts (2023 to 2025), 44 comparison states, state and year fixed effects.\nThe year before the repeal is the reference. Shown for eight years before to two after.",
         x = "Years since the repeal took effect", y = "Change in new NPIs per 100,000 births", caption = "NPPES and NCHS. 95 percent intervals, clustered by state. Post periods are one to two years long.")
  ggsave("figures/fig7_event_study_npi.png", p7, width = 9, height = 5.5, dpi = 150, bg = "white")
}

# ---- 8. Georgia ----------------------------------------------------------------
ga <- panel %>% filter(state == "GA") %>%
  select(year, births, fbc_births, fbc_per_1000_births, home_births, home_per_1000_births, npi_entries, npi_active_stock, con_share_of_year)
write_csv(ga, "output/georgia.csv")
ga_m <- monthly %>% filter(state == "GA") %>% mutate(date = as.Date(paste0(month, "-01")))
write_csv(ga_m, "output/georgia_monthly_npi_entries.csv")

# ---- 9. README tables and headline numbers --------------------------------------
md_table <- function(df, digits = 1) {
  df <- df %>% mutate(across(where(is.numeric) & !any_of(c("year", "Year")), ~ ifelse(abs(.x) >= 1000, comma(.x, accuracy = 1), format(round(.x, digits), nsmall = 0))),
                      across(any_of(c("year", "Year")), as.character))
  paste0("| ", paste(names(df), collapse = " | "), " |\n|", paste(rep("---", ncol(df)), collapse = "|"), "|\n",
         paste0("| ", apply(df, 1, paste, collapse = " | "), " |", collapse = "\n"), "\n")
}
top_bottom <- state24 %>% mutate(rank = row_number()) %>%
  filter(rank <= 8 | rank > n() - 10) %>%
  transmute(Rank = rank, State = state_name, `CON for birth centers (2022)` = ifelse(con_ever == 1, "yes", "no"),
            `Birth center births 2024` = ifelse(fbc_suppressed == 1, "under 10", comma(fbc_births)),
            `Per 1,000 births` = ifelse(fbc_suppressed == 1, "", format(round(fbc_per_1000_births, 1))),
            `Active birth center NPIs` = npi_active_stock)
rep_tab <- rep_panel %>% filter(year %in% c(2016, 2019, 2022, 2024)) %>%
  mutate(v = ifelse(fbc_suppressed == 1, "under 10", as.character(fbc_births))) %>%
  select(state_name, repeal_effective, year, v) %>% pivot_wider(names_from = year, values_from = v) %>%
  left_join(rep_npi %>% filter(year >= 2024) %>% group_by(state_name) %>% summarise(`New NPIs 2024 to Oct 2026` = sum(npi_entries), .groups = "drop"), by = "state_name") %>%
  rename(State = state_name, `CON dropped` = repeal_effective)
sink("output/readme_tables.md")
cat("## 2024 ranking, top and bottom\n\n"); cat(md_table(top_bottom))
cat("\n## The six repeal states: birth center births by residents\n\n"); cat(md_table(rep_tab))
cat("\n## Cross-section, 2022\n\n"); cat(md_table(cs_sum %>% select(group, n, median, mean, share_under_1_per_1000, wilcoxon_p), 3))
cat("\n## Two-way fixed effects\n\n"); cat(md_table(models %>% select(model, estimate, se, p, n, states), 3))
cat("\n## National\n\n"); cat(md_table(national %>% select(year, births, fbc_births, fbc_per_1000, home_per_1000), 2))
sink()
hn <- c(
  sprintf("National birth center births: %s in 2007 (%.1f per 1,000), %s in 2022 (%.1f), %s in 2024 (%.1f)",
          comma(national$fbc_births[national$year == 2007]), national$fbc_per_1000[national$year == 2007],
          comma(national$fbc_births[national$year == 2022]), national$fbc_per_1000[national$year == 2022],
          comma(national$fbc_births[national$year == 2024]), national$fbc_per_1000[national$year == 2024]),
  sprintf("2022 cross-section: median %.1f per 1,000 in CON states (n=%d) vs %.1f in non-CON states (n=%d); Wilcoxon p=%.3f",
          cs_sum$median[cs_sum$con_ever == 1], cs_sum$n[cs_sum$con_ever == 1], cs_sum$median[cs_sum$con_ever == 0], cs_sum$n[cs_sum$con_ever == 0], wt$p.value),
  sprintf("Share of states under 1 per 1,000: CON %.0f%%, non-CON %.0f%%", 100 * cs_sum$share_under_1_per_1000[cs_sum$con_ever == 1], 100 * cs_sum$share_under_1_per_1000[cs_sum$con_ever == 0]),
  sprintf("TWFE, FBC per 1,000 on CON share of year: %.2f (se %.2f, p=%.2f)", models$estimate[1], models$se[1], models$p[1]),
  sprintf("TWFE, NPI entries per 100k births on CON share of year: %.2f (se %.2f, p=%.2f)", models$estimate[3], models$se[3], models$p[3]),
  sprintf("Georgia residents' birth center births: %d (2016), %d (2021), %d (2024); new GA birth center NPIs 2024 to Oct 2026: %d",
          ga$fbc_births[ga$year == 2016], ga$fbc_births[ga$year == 2021], ga$fbc_births[ga$year == 2024], sum(ga$npi_entries[ga$year >= 2024])),
  sprintf("Active birth center NPIs in the 50 states and DC as of October 2026: %s; AABC counted about 400 birth centers in 2022", comma(sum(panel$npi_active_stock[panel$year == 2026]))))
writeLines(hn, "output/headline_numbers.txt"); cat(hn, sep = "\n")
