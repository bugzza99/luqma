import { initializeApp } from 'firebase-admin/app';

initializeApp();

export { onMediaUploaded } from './media/on-upload.js';
export { dailyMaintenance, onOrderDelivered } from './revenue/triggers.js';
