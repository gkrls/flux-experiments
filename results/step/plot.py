import matplotlib.pyplot as plt
import numpy as np
import json
from pathlib import Path

DIR=Path(__file__).parent

with open(DIR / "data.json" ) as f:
  data = json.load(f)

models = ["resnet", "gpt", "roberta", "qwen"]
probabilities = ["0", "5", "10", "15", "20"]

fig, axes = plt.subplots(2, 2, figsize=(12, 10))
axes = axes.flatten()

x_labels = sorted([int(p) for p in probabilities])

data = data["aggressive"]
for idx, model in enumerate(models):
  ax = axes[idx]
  
  ideal_time = np.mean(data["ideal"][model]["avg"])
  
  sa_time_norm = [np.mean(data["sa"][model][str(x)]["avg"]) / ideal_time for x in x_labels]
  su_time_norm = [np.mean(data["su"][model][str(x)]["avg"]) / ideal_time for x in x_labels]
   
  ax.plot(x_labels, sa_time_norm, marker='o', label='SA Time', color='#1f77b4', linewidth=2)
  ax.plot(x_labels, su_time_norm, marker='s', label='SU Time', color='#ff7f0e', linewidth=2)
  
  ax.axhline(y=1.0, color='#d62728', linestyle='--', label='Ideal (1.0)', linewidth=2)
  
  ax.set_title(f'Model: {model.upper()}', fontsize=14, pad=10)
  ax.set_xlabel('Straggle Probability (%)', fontsize=12)
  ax.set_ylabel('Normalized Time (Relative to Ideal)', fontsize=12)
  ax.set_xticks(x_labels) # Ensure the x-axis ticks align exactly with the probability increments
  ax.grid(True, linestyle=':', alpha=0.7)
  ax.legend(loc='best')

plt.tight_layout()
plt.savefig('step.pdf')

plt.show()



for model in models:
    print(f"% ==========================================")
    print(f"% Coordinates for Model: {model.upper()}")
    print(f"% ==========================================\n")
    
    ideal_time = np.mean(data["ideal"][model]["avg"])
    
    sa_coords = []
    su_coords = []
    
    for x in probabilities:
        sa_val = np.mean(data["sa"][model][str(x)]["avg"]) / ideal_time
        su_val = np.mean(data["su"][model][str(x)]["avg"]) / ideal_time
        sa_coords.append(f"({x}, {sa_val:.4f})")
        su_coords.append(f"({x}, {su_val:.4f})")
    
    # Print SA coordinates
    print(f"% SA Line ({model.upper()})")
    print(f"\\addplot coordinates {{ {' '.join(sa_coords)} }};")
    print(f"\\addlegendentry{{SA Time}}\n")
    
    # Print SU coordinates
    print(f"% SU Line ({model.upper()})")
    print(f"\\addplot coordinates {{ {' '.join(su_coords)} }};")
    print(f"\\addlegendentry{{SU Time}}\n")
    
    # Print Ideal coordinates (Horizontal line at y=1.0)
    # We only need the first and last x-values to draw a straight line
    print(f"% Ideal Baseline ({model.upper()})")
    print(f"\\addplot[red, dashed] coordinates {{ ({probabilities[0]}, 1.0000) ({probabilities[-1]}, 1.0000) }};")
    print(f"\\addlegendentry{{Ideal Baseline}}\n")