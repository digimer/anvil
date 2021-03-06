import { useContext } from 'react';

import { Box } from '@material-ui/core';
import { makeStyles } from '@material-ui/core/styles';
import { BodyText, HeaderText } from '../Text';
import { Panel, InnerPanel, PanelHeader } from '../Panels';
import SharedStorageHost from './FileSystemsHost';
import PeriodicFetch from '../../lib/fetchers/periodicFetch';
import { AnvilContext } from '../AnvilContext';
import Spinner from '../Spinner';

const useStyles = makeStyles((theme) => ({
  header: {
    paddingTop: '.1em',
    paddingRight: '.7em',
  },
  root: {
    overflow: 'auto',
    height: '78vh',
    paddingLeft: '.3em',
    [theme.breakpoints.down('md')]: {
      height: '100%',
    },
  },
}));

const SharedStorage = ({ anvil }: { anvil: AnvilListItem[] }): JSX.Element => {
  const classes = useStyles();
  const { uuid } = useContext(AnvilContext);
  const { data, isLoading } = PeriodicFetch<AnvilSharedStorage>(
    `${process.env.NEXT_PUBLIC_API_URL}/get_shared_storage?anvil_uuid=${uuid}`,
  );
  return (
    <Panel>
      <HeaderText text="Shared Storage" />
      {!isLoading ? (
        <Box className={classes.root}>
          {data?.file_systems &&
            data.file_systems.map(
              (fs: AnvilFileSystem): JSX.Element => (
                <InnerPanel key={fs.mount_point}>
                  <PanelHeader>
                    <Box display="flex" width="100%" className={classes.header}>
                      <Box>
                        <BodyText text={fs.mount_point} />
                      </Box>
                    </Box>
                  </PanelHeader>
                  {fs?.hosts &&
                    fs.hosts.map(
                      (
                        host: AnvilFileSystemHost,
                        index: number,
                      ): JSX.Element => (
                        <SharedStorageHost
                          host={{
                            ...host,
                            ...anvil[
                              anvil.findIndex((a) => a.anvil_uuid === uuid)
                            ].hosts[index],
                          }}
                          key={fs.hosts[index].free}
                        />
                      ),
                    )}
                </InnerPanel>
              ),
            )}
        </Box>
      ) : (
        <Spinner />
      )}
    </Panel>
  );
};

export default SharedStorage;
