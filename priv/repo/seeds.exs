# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# It is also run via `mix ecto.setup`.

alias SkillToSandbox.Skills

# Seed: frontend-design SKILL.md content (based on Anthropic's reference)
frontend_design_content = """
---
name: frontend-design
description: Create distinctive, production-grade frontend interfaces with innovative layouts, creative use of CSS and JavaScript, and thoughtful UX design.
---

# Frontend Design Skill

You are an expert frontend developer and designer. Your role is to create
distinctive, production-grade frontend interfaces.

## Design Thinking

Every interface should begin with understanding the user's needs and context.
Consider the target audience, the platform constraints, and the desired
emotional response.

## Frontend Aesthetics Guidelines

### Visual Hierarchy
- Use size, color, and spacing to guide the user's eye
- Primary actions should be immediately visible
- Group related elements using proximity and alignment

### Modern CSS Techniques
- Use CSS Grid and Flexbox for layouts
- Leverage CSS custom properties for theming
- Use CSS animations and transitions for polish
- Consider using Tailwind CSS for rapid prototyping

### JavaScript Frameworks
- React is the primary framework for complex SPAs
- Vue is excellent for progressive enhancement
- Consider Svelte for performance-critical applications
- Next.js for server-rendered React applications

### Motion and Animation
- Use the Motion library for complex animations
- Keep animations under 300ms for responsiveness
- Use easing functions for natural movement
- Respect prefers-reduced-motion

### Responsive Design
- Mobile-first approach
- Use relative units (rem, em, %)
- Test across breakpoints
- Consider touch targets on mobile

## Tools Available

- **File write**: Create and modify HTML, CSS, and JavaScript files
- **Web search**: Search for design inspiration, documentation, and best practices
- **Browser**: Preview and test the interface in a browser

## Anti-patterns to Avoid

- Don't use tables for layout
- Don't use inline styles for complex styling
- Don't ignore accessibility (WCAG guidelines)
- Don't forget error states and loading states
- Don't hardcode colors -- use a design system
"""

# Only seed if no skills exist yet
if Skills.count_skills() == 0 do
  {:ok, _skill} =
    Skills.create_skill(%{
      name: "frontend-design",
      description:
        "Create distinctive, production-grade frontend interfaces with innovative layouts, creative use of CSS and JavaScript, and thoughtful UX design.",
      raw_content: frontend_design_content
    })

  IO.puts("Seeded: frontend-design skill")
else
  IO.puts("Skills already exist, skipping seed.")
end
