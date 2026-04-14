import { Router } from 'express';
import type { HealthResponse } from '@moviekaraoke/shared';

export const healthRouter = Router();

healthRouter.get('/health', (_req, res) => {
  const response: HealthResponse = {
    status: 'ok',
    timestamp: new Date().toISOString(),
  };
  res.json(response);
});
