import { useContext } from 'react';
import { Panel } from '../Panels';
import { HeaderText } from '../Text';
import AnvilHost from './AnvilHost';
import PeriodicFetch from '../../lib/fetchers/periodicFetch';
import { AnvilContext } from '../AnvilContext';
import Spinner from '../Spinner';
import hostsSanitizer from '../../lib/sanitizers/hostsSanitizer';

const Hosts = ({ anvil }: { anvil: AnvilListItem[] }): JSX.Element => {
  const { uuid } = useContext(AnvilContext);

  const { data, isLoading } = PeriodicFetch<AnvilStatus>(
    `${process.env.NEXT_PUBLIC_API_URL}/get_status?anvil_uuid=${uuid}`,
  );

  const anvilIndex = anvil.findIndex((a) => a.anvil_uuid === uuid);

  return (
    <Panel>
      <HeaderText text="Nodes" />
      {!isLoading ? (
        <>
          {anvilIndex !== -1 && data && (
            <AnvilHost
              hosts={hostsSanitizer(anvil[anvilIndex].hosts).map(
                (host, index) => {
                  return data.hosts[index];
                },
              )}
            />
          )}
        </>
      ) : (
        <Spinner />
      )}
    </Panel>
  );
};

export default Hosts;
