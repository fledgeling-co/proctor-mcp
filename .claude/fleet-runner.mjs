export const meta = {
  name: 'proctor-fleet-runner',
  description: 'Fleet runner for one proctor-mcp feature (opus, high effort)',
  phases: [{ title: 'Run' }],
}

const a = typeof args === 'string' ? JSON.parse(args) : args
if (!a || typeof a.prompt !== 'string' || a.prompt.length < 100)
  throw new Error('args.prompt missing — abort before spawning')

phase('Run')
return await agent(a.prompt, {
  label: `runner:${a.id || 'unknown'}`,
  model: 'opus',
  effort: 'high',
  agentType: 'claude',
})
