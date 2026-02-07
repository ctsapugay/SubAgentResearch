Goal: Pipeline to train small models based on existing subagent/skills so those small models can be used in place of larger models when that subagent/skill would be used.

Claude Code: Create a website  
—\> Research react js node  
—--\> subagent … (a lot of research), read file tools, web search, etc. Returns natural language answer that's compact and a summary of all the information

Typically, we just use a large model (perhaps a little weaker than your main orchestrator) to do these subagents. BUT, subagents/skills are specialized, so there's an opportunity for us to train smaller models to replace them, thus being cheaper, more privacy, etc.

```
Def subagent(prompt, config):
"""
Prompt : what we want to accomplish
Config: defines the subagent, i.e., system prompt, tools, environment

Returns text about what we want to accomplish/some file paths (this can be really anything as long as it's condensed, just shorter than its trace)
"""
```

We provide the subagent tool to the orchestrator (which is just an LLM). Orchestrator might have it's own tools, perhaps simple filesystem tools (MassGen primitives)

### Part 1

Goal: Create a local LLM with the role of the skill/subagent.

Skill/subagent \-\> tools, sandbox environment to create a container & come up with a set of goals for which the model must accomplish \-\> generate synthetic data, finetune small model (distillation based where use a large powerful model within our container \+ synthetic data to train the small model) \-\> small LM finetuned to do the skill/subagent.  
—\> SFT (can be from a different model family)  
—\> (Later) RL if deemed useful but SFT is likely strong enough for yeah.

*\*Note: Will be useful to find centralized skill/subagent libraries (i.e., where there are large selections of skills, widely adopted, and usable); may want some nice way to search over them to find relevant ones given a task. E.g., 'web design' \-\> skills related to web design. We can just ask an LLM for this/use embeddings if necessary but probably not\*.*

Benefit of this approach: there's a rich collection of existing skills/subagents that people have validate through use, constant releases of these that show much improvement using them vs not using them. E.g., [https://github.com/anthropics/claude-code/blob/main/plugins/frontend-design/skills/frontend-design/SKILL.md](https://github.com/anthropics/claude-code/blob/main/plugins/frontend-design/skills/frontend-design/SKILL.md)

Synthetic data: [https://github.com/always-further/deepfabric?tab=readme-ov-file](https://github.com/always-further/deepfabric?tab=readme-ov-file)  
→ Come up a set of diverse prompts  
→ Generate data with a large powerful model – date \== traces:

```
I need to call web search to research good design practices [REASONING]

web_search('What are ...') [TOOL CALL]
-> returns{} [TOOL RESPONSE]

I found that we should prioritize clean... [REASONING]
...
Final answer
```

Related work for training coding agent: [https://allenai.org/blog/open-coding-agents](https://allenai.org/blog/open-coding-agents)

Tasks:

1. How to get from skill/subagent to sandbox?  
2. How to get from skill/subagent \+ sandbox to synthetic training data?  
3. How to train the model from training data?  
   1. What models do want to use (Qwen3-4B?) LoRA SFT

### 

### Part 2

How do we make use of these models?

Given the large set of skills/subagents available, we will choose N useful ones that relate to M certain benchmarks.

Given we have an orchestrator (LLM, probably large for better planning abilities) with the ability to call subagents, how can we produce a better answer.  
—\> Baselines: Using large models as subagents, using small models as subagents (without training), ours

Challenge: when to call subagents, which to call. Is there a difference when we use subagents w/o training vs our subagents?

Tasks:

1. What benchmarks to choose?  
2. What skills/subagents to choose (based on benchmarks)  
3. Given the set of skills/subagents, how do we call them well to get a better answer?  
   1. Is there anything different about our local models to keep in mind here? Anything we can use in this step to go back and train the subagent models a little differently to improve performance?
