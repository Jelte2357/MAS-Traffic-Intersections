library(gvlma)
library(performance)
library(dplyr)
library(gridExtra)
library(ggplot2)
library(car)
# How does increasing car demand affect traffic throughput efficiency for different intersection designs?
# Which intersection type maintains the highest throughput efficiency under high car demand, and how sensitive is it to additional bike traffic?


# Calculate total time in the model
patches_across = 500
real_distance_m = 50
patches_realsize_m = real_distance_m / patches_across
dist_per_tick = patches_realsize_m * 6
average_speed = 25 / 3.6 # km/h -> m/s
ticks_per_second = average_speed / dist_per_tick
seconds_per_tick = 1 / ticks_per_second
total_duration_mins = 10000 * seconds_per_tick / 60
print(total_duration_mins) # 14.4


df <- read.csv("results_table.csv")

# Plot the box plots for max cars 1, 3, 5 (at which the switch happens)
dfs <- subset(df, (max_cars %in% c(1,3,5))) # 1, 3, 5 max cars
dfs$map_layout_code <- as.factor(dfs$map_layout_code)
p1 <- ggplot(dfs, aes(x=map_layout_code, y = throughput, color= map_layout_code)) +
  geom_boxplot() + 
  geom_jitter() + 
  facet_grid(.~max_cars) + 
  theme_bw() +
  labs(
    title = "Throughput by map layout code and maximum cars (1, 3 & 5)",
    x = "Map Layout Code",
    y = "Throughput",
    color = "Map Layout Code"
  )+
  theme(plot.title = element_text(hjust = 0.5)) # center title
p1

# Anova + TukeyHSD for map layout code on its own.
df$map_layout_code <- as.factor(dfs$map_layout_code)
anova_model <- aov(throughput ~ map_layout_code, data=dfs)
summary(anova_model)
tukey_res <- TukeyHSD(anova_model)
print(tukey_res)

# Same adding bikes
dfs <- subset(df, (max_cars %in% c(1,3,5)))
p2 <- ggplot(dfs, aes(x=map_layout_code, y = throughput, color= map_layout_code)) +
  geom_boxplot()+
  geom_jitter()+
  facet_grid(max_bikes~.)
p2


for (n in c(1,3,5,7,9,11,13)) {
  cat("\n=== Max cars =", n, "===\n")
  sub <- subset(df, max_cars == n)
  sub$map_layout_code <- as.factor(sub$map_layout_code)
  
  mlc <- aov(throughput ~ map_layout_code, data=sub)
  mlc_mb <- aov(throughput ~ map_layout_code + max_bikes, data=sub)
  
  # print(shapiro.test(residuals(a)))
  # print(leveneTest(throughput ~ map_layout_code, data=sub))
  
  print(summary(mlc))
  print(summary(mlc_mb))
  
  print(TukeyHSD(a))
}
