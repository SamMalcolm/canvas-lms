/*
 * Copyright (C) 2018 - present Instructure, Inc.
 *
 * This file is part of Canvas.
 *
 * Canvas is free software: you can redistribute it and/or modify it under
 * the terms of the GNU Affero General Public License as published by the Free
 * Software Foundation, version 3 of the License.
 *
 * Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
 * WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
 * A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
 * details.
 *
 * You should have received a copy of the GNU Affero General Public License along
 * with this program. If not, see <http://www.gnu.org/licenses/>.
 */

import Enzyme from 'enzyme'
import Adapter from 'enzyme-adapter-react-16'

const errorsToIgnore = ["Warning: [Focusable] Exactly one tabbable child is required (0 found)."];

window.fetch = require('jest-fetch-mock')

/* eslint-disable-next-line */
const _consoleDotError = console.error
/* eslint-disable-next-line */
console.error = function (message) {
      if(errorsToIgnore.includes(message)) return
      _consoleDotError.apply(this, arguments)
    }

window.scroll = () => {}
window.ENV = {}

Enzyme.configure({ adapter: new Adapter() })

// because InstUI themeable components need an explicit "dir" attribute on the <html> element
document.documentElement.setAttribute('dir', 'ltr')

require('@instructure/ui-themes')

if (process.env.DEPRECATION_SENTRY_DSN) {
  const Raven = require('raven-js')
  Raven.config(process.env.DEPRECATION_SENTRY_DSN, {
    ignoreErrors: ['renderIntoDiv', 'renderSidebarIntoDiv'], // silence the `Cannot read property 'renderIntoDiv' of null` errors we get from the pre- rce_enhancements old rce code
    release: process.env.GIT_COMMIT
  }).install();

  const setupRavenConsoleLoggingPlugin = require('../app/jsx/shared/helpers/setupRavenConsoleLoggingPlugin').default;
  setupRavenConsoleLoggingPlugin(Raven, { loggerName: 'console-jest' });
}

// set up mocks for native APIs
if (!('MutationObserver' in window)) {
  Object.defineProperty(window, 'MutationObserver', { value: require('@sheerun/mutationobserver-shim') })
}
