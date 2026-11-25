/*
 * Acción propia de Scaffolder: ejecuta un Golden Path de la PoC con `make`.
 * La lógica vive en gp/*.py y en el Makefile del repo; Backstage solo es el front.
 */
import { createBackendModule } from '@backstage/backend-plugin-api';
import {
  createTemplateAction,
  scaffolderActionsExtensionPoint,
} from '@backstage/plugin-scaffolder-node';
import { spawn } from 'node:child_process';
import path from 'node:path';

const REPO_ROOT = process.env.POC_REPO_ROOT ?? path.resolve(process.cwd(), '../..');

const ejecutarGp = createTemplateAction({
  id: 'poc:ejecutar-gp',
  description: 'Ejecuta el GP publicador o suscriptor de la PoC con make.',
  schema: {
    input: zImpl =>
      zImpl.object({
      target: zImpl.enum(['gp-publicador', 'gp-suscriptor']),
      service: zImpl.string(),
      owner: zImpl.string(),
      costCenter: zImpl.string(),
      desde: zImpl.enum(['inicio', 'nuevos']).optional(),
      }),
  },
  async handler(ctx) {
    const { target, service, owner, costCenter, desde } = ctx.input;
    const vars =
      target === 'gp-publicador'
        ? [`SERVICE=${service}`]
        : [`SUSCRIPTOR=${service}`, `DESDE=${desde ?? 'inicio'}`];
    const args = [target, ...vars, `OWNER=${owner}`, `COST_CENTER=${costCenter}`];
    ctx.logger.info(`make ${args.join(' ')} (en ${REPO_ROOT})`);

    await new Promise<void>((resolve, reject) => {
      const proc = spawn('make', args, { cwd: REPO_ROOT, env: process.env });
      const log = (chunk: Buffer) =>
        chunk
          .toString()
          .split('\n')
          .filter(Boolean)
          .forEach(line => ctx.logger.info(line));
      proc.stdout.on('data', log);
      proc.stderr.on('data', log);
      proc.on('error', reject);
      proc.on('close', code =>
        code === 0 ? resolve() : reject(new Error(`make ${target} terminó con código ${code}`)),
      );
    });

    ctx.output('repoLocal', `generated/${service}`);
  },
});

export default createBackendModule({
  pluginId: 'scaffolder',
  moduleId: 'poc-actions',
  register(reg) {
    reg.registerInit({
      deps: { scaffolder: scaffolderActionsExtensionPoint },
      async init({ scaffolder }) {
        scaffolder.addActions(ejecutarGp);
      },
    });
  },
});
